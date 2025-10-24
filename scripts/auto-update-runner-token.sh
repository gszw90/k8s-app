#!/bin/bash

# 自动化Runner Token更新脚本 (CronJob友好版本)

set -e

APP_ID="2168366"
INSTALLATION_ID="91349326"
PRIVATE_KEY_FILE="./config/github-app-private-key.pem"
REPO="gszw90/k8s-app"
NAMESPACE="github-runners"
SECRET_NAME="github-runner-secret"
DEPLOYMENT_NAME="github-runner-simple"

# 生成JWT Token
generate_jwt() {
    local header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 -w 0 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    local iat=$(date +%s)
    local exp=$((iat + 600))
    local payload=$(echo -n "{\"iat\":$iat,\"exp\":$exp,\"iss\":$APP_ID}" | base64 -w 0 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    local signature=$(echo -n "${header}.${payload}" | openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" | base64 -w 0 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    echo "${header}.${payload}.${signature}"
}

# 获取Runner Token
get_runner_token() {
    local jwt_token="$1"
    local access_token=$(curl -s -X POST -H "Authorization: Bearer $jwt_token" -H "Accept: application/vnd.github.v3+json" https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens | jq -r '.token')
    curl -s -X POST -H "Authorization: token $access_token" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$REPO/actions/runners/registration-token | jq -r '.token'
}

# 更新Secret
update_secret() {
    local token="$1"
    local encoded_token=$(echo -n "$token" | base64 -w 0)
    kubectl patch secret "$SECRET_NAME" -n "$NAMESPACE" -p "{\"data\":{\"RUNNER_TOKEN\":\"$encoded_token\"}}" --type=merge
}

# 主流程
main() {
    echo "[$(date)] 开始自动更新Runner Token..."

    # 生成JWT
    local jwt=$(generate_jwt)

    # 获取Runner Token
    local runner_token=$(get_runner_token "$jwt")
    echo "Token长度: ${#runner_token}"

    # 验证token
    if [[ ${#runner_token} -lt 20 ]]; then
        echo "错误: Token长度异常"
        exit 1
    fi

    # 更新secret
    update_secret "$runner_token"
    echo "Secret更新成功"

    # 重启deployment (可选)
    if [[ "$1" == "--restart" ]]; then
        kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
        echo "Deployment重启成功"
    fi

    echo "✅ Runner Token自动更新完成"
}

# 执行
main "$@"