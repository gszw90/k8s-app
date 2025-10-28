#!/bin/bash

# kubectl缓存更新脚本
# 支持手动触发kubectl版本更新

set -e

# 配置变量
NAMESPACE="github-runners"
DEPLOYMENT_NAME="kubectl-cache-manager"
DEFAULT_VERSION="v1.32.2"

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

print_warning() {
    echo -e "⚠️  $1"
}

# 显示帮助信息
show_help() {
    echo "kubectl缓存更新脚本"
    echo ""
    echo "用法: $0 [选项] [版本]"
    echo ""
    echo "选项:"
    echo "  -v, --version VERSION   指定kubectl版本 (默认: $DEFAULT_VERSION)"
    echo "  -s, --strategy STRATEGY  更新策略: manual|automatic (默认: manual)"
    echo "  -f, --force             强制更新，即使版本相同"
    echo "  -c, --check             仅检查当前状态，不执行更新"
    echo "  -h, --help              显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                                    # 使用默认版本更新"
    echo "  $0 v1.31.0                            # 更新到指定版本"
    echo "  $0 --version v1.32.0 --strategy auto # 自动策略更新"
    echo "  $0 --check                            # 检查当前状态"
    echo ""
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖..."

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl未安装"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "无法连接到Kubernetes集群"
        exit 1
    fi

    print_success "依赖检查通过"
}

# 检查当前状态
check_current_status() {
    print_info "检查kubectl缓存管理器状态..."

    # 检查Pod状态
    local pod_status=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    print_info "Pod状态: $pod_status"

    # 检查kubectl版本
    local kubectl_version=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT_NAME -- /shared/kubectl version --client --short 2>/dev/null || echo "Unknown")
    print_info "当前kubectl版本: $kubectl_version"

    # 检查更新策略
    local update_strategy=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPDATE_STRATEGY")].value}' 2>/dev/null || echo "Unknown")
    print_info "更新策略: $update_strategy"

    # 检查共享卷状态
    local pvc_status=$(kubectl get pvc kubectl-cache-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    print_info "共享卷状态: $pvc_status"

    # 检查kubectl文件大小
    local kubectl_size=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT_NAME -- ls -la /shared/kubectl 2>/dev/null | awk '{print $5}' || echo "0")
    if [[ "$kubectl_size" -gt 0 ]]; then
        print_success "kubectl文件大小: $kubectl_size bytes"
    else
        print_warning "kubectl文件不存在或为空"
    fi
}

# 更新kubectl版本
update_kubectl() {
    local version="$1"
    local strategy="$2"
    local force="$3"

    print_info "开始更新kubectl缓存..."
    print_info "目标版本: $version"
    print_info "更新策略: $strategy"

    # 检查当前版本
    local current_version=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT_NAME -- /shared/kubectl version --client --short 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")

    if [[ "$current_version" == "$version" && "$force" != "true" ]]; then
        print_warning "当前版本已是 $version，使用 --force 强制更新"
        return 0
    fi

    # 更新环境变量
    print_info "更新kubectl版本配置..."
    kubectl set env deployment/$DEPLOYMENT_NAME KUBECTL_VERSION=$UPDATE_VERSION -n $NAMESPACE
    kubectl set env deployment/$DEPLOYMENT_NAME UPDATE_STRATEGY=$UPDATE_STRATEGY -n $NAMESPACE

    # 触发重启（通过更新注解）
    print_info "触发缓存管理器重启..."
    kubectl annotate deployment $DEPLOYMENT_NAME kubectl.io/update-trigger=$(date +%s) -n $NAMESPACE --overwrite

    # 重启Deployment
    print_info "重启缓存管理器..."
    kubectl rollout restart deployment/$DEPLOYMENT_NAME -n $NAMESPACE

    # 等待重启完成
    print_info "等待缓存管理器就绪..."
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s

    if [ $? -eq 0 ]; then
        print_success "kubectl缓存更新完成"

        # 验证更新结果
        sleep 10
        local new_version=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT_NAME -- /shared/kubectl version --client --short 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
        print_success "更新后版本: $new_version"
    else
        print_error "kubectl缓存更新失败"
        exit 1
    fi
}

# 主函数
main() {
    local version="$DEFAULT_VERSION"
    local strategy="manual"
    local force="false"
    local check_only="false"

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                version="$2"
                shift 2
                ;;
            -s|--strategy)
                strategy="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            -c|--check)
                check_only="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                version="$1"
                shift
                ;;
        esac
    done

    # 验证参数
    if [[ "$strategy" != "manual" && "$strategy" != "automatic" ]]; then
        print_error "无效的更新策略: $strategy (支持: manual, automatic)"
        exit 1
    fi

    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "无效的版本格式: $version (示例: v1.32.2)"
        exit 1
    fi

    # 导出变量供后续使用
    export UPDATE_VERSION="$version"
    export UPDATE_STRATEGY="$strategy"

    echo "🔄 kubectl缓存更新工具"
    echo "===================="

    check_dependencies

    if [[ "$check_only" == "true" ]]; then
        check_current_status
        exit 0
    fi

    check_current_status
    update_kubectl "$version" "$strategy" "$force"

    print_success "kubectl缓存更新流程完成！"
}

# 执行主函数
main "$@"