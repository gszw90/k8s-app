#!/bin/bash

# GitHub App Runner Token自动更新脚本
# 使用GitHub App认证，彻底解决token过期问题

set -e

echo "🔑 GitHub App Runner Token自动更新"
echo "================================"

# 配置变量
APP_ID="2168366"
INSTALLATION_ID="91349326"
PRIVATE_KEY_FILE="./config/github-app-private-key.pem"
REPO="gszw90/k8s-app"
NAMESPACE="github-runners"
DEPLOYMENT_NAME="github-runner-simple"
SECRET_NAME="github-runner-secret"

# 关闭颜色输出
export NO_COLOR=1

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
}

info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
}

# 检查依赖
check_dependencies() {
    log "🔍 检查依赖..."

    local required_tools=("kubectl" "jq" "openssl" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "缺少必要工具: $tool"
            exit 1
        fi
    done

    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        error "GitHub App私钥文件不存在: $PRIVATE_KEY_FILE"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        error "无法连接到Kubernetes集群"
        exit 1
    fi

    log "✅ 依赖检查通过"
}

# 生成清洁的JWT Token
generate_clean_jwt() {
    log "🔐 生成GitHub App JWT Token..."

    local header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 -w 0 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    local iat=$(date +%s)
    local exp=$((iat + 600))
    local payload=$(echo -n "{\"iat\":$iat,\"exp\":$exp,\"iss\":$APP_ID}" | base64 -w 0 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    local signature=$(echo -n "${header}.${payload}" | openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" | base64 -w 0 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    echo "${header}.${payload}.${signature}"
}

# 获取GitHub App Access Token
get_app_access_token() {
    local jwt_token="$1"
    log "🔑 获取GitHub App Access Token..."

    local response=$(curl -s -X POST \
        -H "Authorization: Bearer $jwt_token" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens)

    local access_token=$(echo "$response" | jq -r '.token')

    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
        error "无法获取Access Token"
        error "响应: $response"
        exit 1
    fi

    log "✅ GitHub App Access Token获取成功"
    echo "$access_token"
}

# 生成Runner Registration Token
generate_runner_token() {
    local app_access_token="$1"
    log "🏃 生成Runner Registration Token..."

    local response=$(curl -s -X POST \
        -H "Authorization: token $app_access_token" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/$REPO/actions/runners/registration-token)

    local runner_token=$(echo "$response" | jq -r '.token')

    if [[ -z "$runner_token" || "$runner_token" == "null" ]]; then
        error "无法生成Runner Token"
        error "响应: $response"
        exit 1
    fi

    log "✅ Runner Token生成成功"
    echo "$runner_token"
}

# 更新Kubernetes Secret
update_k8s_secret() {
    local runner_token="$1"
    log "🔄 更新Kubernetes Secret..."

    local clean_token=$(echo -n "$runner_token" | tr -d '\n\r' | base64 -w 0)

    kubectl patch secret "$SECRET_NAME" \
        -n "$NAMESPACE" \
        -p "{\"data\":{\"RUNNER_TOKEN\":\"$clean_token\"}}" \
        --type=merge

    if [ $? -eq 0 ]; then
        log "✅ Secret更新成功"
    else
        error "Secret更新失败"
        exit 1
    fi
}

# 重启Runner Deployment
restart_runner_deployment() {
    log "🔄 重启Runner Deployment..."

    kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"

    if [ $? -eq 0 ]; then
        log "✅ Deployment重启成功"
    else
        error "Deployment重启失败"
        exit 1
    fi
}

# 验证Token有效性
verify_token() {
    local runner_token="$1"
    log "🔍 验证Token有效性..."

    if [[ ${#runner_token} -lt 20 ]]; then
        error "Token长度异常: ${#runner_token}"
        return 1
    fi

    if [[ "$runner_token" =~ [[:cntrl:]] ]]; then
        error "Token包含控制字符"
        return 1
    fi

    log "✅ Token格式验证通过"
    return 0
}

# 主函数
main() {
    local force_update=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force_update=true
                shift
                ;;
            --help|-h)
                echo "用法: $0 [--force|-f] [--help|-h]"
                echo ""
                echo "选项:"
                echo "  --force, -f    强制更新token"
                echo "  --help, -h     显示此帮助信息"
                exit 0
                ;;
            *)
                error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    log "开始GitHub App Runner Token更新流程..."

    check_dependencies

    local jwt_token=$(generate_clean_jwt)
    info "JWT Token生成完成"

    local app_access_token=$(get_app_access_token "$jwt_token")
    info "App Access Token获取完成"

    local runner_token=$(generate_runner_token "$app_access_token")
    info "Runner Token生成完成"

    if ! verify_token "$runner_token"; then
        error "Token验证失败"
        exit 1
    fi

    update_k8s_secret "$runner_token"
    restart_runner_deployment

    log "🎉 GitHub App Runner Token更新完成！"
    info "Token有效期: 约1小时"
}

# 执行主函数
main "$@"