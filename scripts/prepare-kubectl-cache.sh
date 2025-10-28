#!/bin/bash

# GitHub Runner kubectl预下载和缓存脚本
# 将kubectl二进制文件预先下载并存储为ConfigMap

set -e

echo "📦 准备kubectl二进制缓存..."

# 配置变量
NAMESPACE="github-runners"
CONFIGMAP_NAME="kubectl-binary"
KUBECTL_VERSION="v1.32.2"  # 可以更新为最新版本

# 颜色输出函数
print_success() {
    echo -e "✅ $1"
}

print_error() {
    echo -e "❌ $1"
}

print_info() {
    echo -e "ℹ️  $1"
}

# 检查依赖
check_dependencies() {
    print_info "检查下载依赖..."

    if ! command -v curl &> /dev/null; then
        print_error "curl未安装，请先安装curl"
        exit 1
    fi

    if ! command -v base64 &> /dev/null; then
        print_error "base64未安装，请先安装base64"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl未安装，请先安装kubectl"
        exit 1
    fi

    print_success "依赖检查通过"
}

# 下载kubectl二进制文件
download_kubectl() {
    print_info "下载kubectl二进制文件..."

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # 获取最新稳定版本（如果未指定）
    if [[ "$KUBECTL_VERSION" == "latest" ]]; then
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        print_info "检测到最新版本: $KUBECTL_VERSION"
    fi

    # 下载kubectl
    print_info "下载kubectl版本: $KUBECTL_VERSION"
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

    # 验证下载
    if [[ -f "kubectl" ]]; then
        print_success "kubectl下载成功"

        # 验证二进制文件
        if ./kubectl version --client &> /dev/null; then
            VERSION_INFO=$(./kubectl version --client --short 2>/dev/null || echo "unknown")
            print_info "kubectl版本: $VERSION_INFO"
        else
            print_error "kubectl二进制文件验证失败"
            exit 1
        fi
    else
        print_error "kubectl下载失败"
        exit 1
    fi

    # 返回到原目录
    cd - >/dev/null
    echo "$TEMP_DIR/kubectl"
}

# 编码并更新ConfigMap
update_configmap() {
    local kubectl_path="$1"
    print_info "编码kubectl二进制文件并更新ConfigMap..."

    # 检查kubectl文件
    if [[ ! -f "$kubectl_path" ]]; then
        print_error "kubectl文件不存在: $kubectl_path"
        exit 1
    fi

    # 获取文件大小
    FILE_SIZE=$(stat -c%s "$kubectl_path")
    print_info "kubectl文件大小: $FILE_SIZE bytes"

    # 编码为base64
    print_info "编码为base64..."
    KUBECTL_BASE64=$(base64 -w 0 "$kubectl_path")

    # 检查编码结果
    if [[ -n "$KUBECTL_BASE64" ]]; then
        print_success "base64编码完成，长度: ${#KUBECTL_BASE64} 字符"
    else
        print_error "base64编码失败"
        exit 1
    fi

    # 检查命名空间是否存在
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        print_info "创建命名空间: $NAMESPACE"
        kubectl create namespace $NAMESPACE
    fi

    # 更新ConfigMap
    print_info "更新ConfigMap: $CONFIGMAP_NAME"

    # 使用patch更新（如果存在）或创建新的ConfigMap
    if kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE &> /dev/null; then
        # 更新现有ConfigMap
        kubectl patch configmap $CONFIGMAP_NAME -n $NAMESPACE -p "{\"data\":{\"kubectl\":\"${KUBECTL_BASE64}\"}}"
        print_success "ConfigMap更新成功"
    else
        # 创建新ConfigMap
        kubectl create configmap $CONFIGMAP_NAME -n $NAMESPACE --from-literal=kubectl="$KUBECTL_BASE64"
        print_success "ConfigMap创建成功"
    fi

    # 验证ConfigMap
    print_info "验证ConfigMap..."
    STORED_SIZE=$(kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.kubectl}' | wc -c)
    if [[ $STORED_SIZE -gt 0 ]]; then
        print_success "ConfigMap验证成功，存储大小: $STORED_SIZE 字符"
    else
        print_error "ConfigMap验证失败"
        exit 1
    fi
}

# 测试ConfigMap
test_configmap() {
    print_info "测试kubectl ConfigMap..."

    # 创建测试Pod
    TEST_POD="kubectl-test-$(date +%s)"

    kubectl run $TEST_POD \
        --image=busybox:1.35 \
        --rm -i \
        --restart=Never \
        --namespace=$NAMESPACE \
        --command=/bin/sh \
        -- \
        -c " \
            echo '测试kubectl ConfigMap...' && \
            mkdir -p /opt/kubectl && \
            base64 -d /opt/kubectl/kubectl > /usr/local/bin/kubectl && \
            chmod +x /usr/local/bin/kubectl && \
            /usr/local/bin/kubectl version --client && \
            echo '✅ ConfigMap测试成功' \
        "

    if [ $? -eq 0 ]; then
        print_success "kubectl ConfigMap测试通过"
    else
        print_error "kubectl ConfigMap测试失败"
        return 1
    fi
}

# 清理临时文件
cleanup() {
    local temp_dir="$1"
    if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        print_info "清理临时文件: $temp_dir"
    fi
}

# 显示信息
show_info() {
    print_info "配置信息:"
    echo "  📦 kubectl版本: $KUBECTL_VERSION"
    echo "  🏷️  命名空间: $NAMESPACE"
    echo "  📋 ConfigMap: $CONFIGMAP_NAME"
    echo ""

    print_info "下一步:"
    echo "  1. 应用RBAC权限配置: kubectl apply -f deploy/k8s/github-runner-enhanced-serviceaccount.yaml"
    echo "  2. 部署优化版Runner: kubectl apply -f deploy/k8s/github-runner-optimized-deployment.yaml"
    echo "  3. 验证部署状态: ./scripts/deploy-enhanced-runner.sh verify"
    echo ""
}

# 主函数
main() {
    local action="${1:-prepare}"

    case "$action" in
        "prepare")
            echo "🚀 开始准备kubectl缓存..."
            check_dependencies

            KUBECTL_PATH=$(download_kubectl)
            update_configmap "$KUBECTL_PATH"
            test_configmap
            show_info

            # 清理临时文件
            cleanup "$(dirname "$KUBECTL_PATH")"

            print_success "kubectl缓存准备完成！"
            ;;
        "test")
            echo "🔍 测试kubectl ConfigMap..."
            test_configmap
            ;;
        "cleanup")
            echo "🗑️ 清理kubectl ConfigMap..."
            kubectl delete configmap $CONFIGMAP_NAME -n $NAMESPACE
            print_success "ConfigMap清理完成"
            ;;
        "info")
            show_info
            ;;
        "help"|"-h"|"--help")
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  prepare  - 准备kubectl缓存（默认）"
            echo "  test     - 测试ConfigMap"
            echo "  cleanup  - 清理ConfigMap"
            echo "  info     - 显示配置信息"
            echo "  help     - 显示帮助信息"
            ;;
        *)
            print_error "未知命令: $action"
            echo "使用 '$0 help' 查看可用命令"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"