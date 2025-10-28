#!/bin/bash

# GitHub Runner Enhanced 部署脚本
# 部署支持Pod内Kubernetes通信的增强版Runner

set -e

echo "🚀 开始部署GitHub Runner Enhanced (Pod内Kubernetes通信方案)"
echo "=================================================================="

# 配置变量
NAMESPACE="github-runners"
DEPLOYMENT_NAME="github-runner-enhanced"
CONFIG_FILE="deploy/k8s/github-runner-complete-setup.yaml"

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

# 检查依赖
check_dependencies() {
    print_info "检查部署依赖..."

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl未安装，请先安装kubectl"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "无法连接到Kubernetes集群"
        exit 1
    fi

    print_success "依赖检查通过"
}

# 备份现有配置
backup_existing() {
    print_info "备份现有配置..."

    if kubectl get deployment github-runner-simple -n $NAMESPACE &> /dev/null; then
        BACKUP_DIR="backup/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"

        print_info "备份现有Runner配置到: $BACKUP_DIR"
        kubectl get deployment github-runner-simple -n $NAMESPACE -o yaml > "$BACKUP_DIR/github-runner-simple.yaml" || true

        # 备份相关配置
        kubectl get serviceaccount github-runner-actions-sa -n $NAMESPACE -o yaml > "$BACKUP_DIR/serviceaccount.yaml" 2>/dev/null || true

        print_success "备份完成"
    else
        print_info "未找到现有Runner配置，跳过备份"
    fi
}

# 部署新配置
deploy_enhanced_runner() {
    print_info "部署增强版GitHub Runner..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi

    # 应用配置
    print_info "应用Kubernetes配置..."
    kubectl apply -f "$CONFIG_FILE"

    if [ $? -eq 0 ]; then
        print_success "配置应用成功"
    else
        print_error "配置应用失败"
        exit 1
    fi
}

# 等待部署完成
wait_for_deployment() {
    print_info "等待部署完成..."

    # 等待Pod创建
    print_info "等待Pod启动..."
    kubectl wait --for=condition=available \
        deployment/$DEPLOYMENT_NAME \
        -n $NAMESPACE \
        --timeout=300s

    if [ $? -eq 0 ]; then
        print_success "部署完成"
    else
        print_warning "部署超时，但可能仍在进行中"
    fi
}

# 验证部署
verify_deployment() {
    print_info "验证部署状态..."

    # 检查Pod状态
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")

    if [[ "$POD_STATUS" == "Running" ]]; then
        print_success "Pod运行状态: $POD_STATUS"
    else
        print_warning "Pod状态: $POD_STATUS"
    fi

    # 检查就绪状态
    READY_STATUS=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

    if [[ "$READY_STATUS" == "True" ]]; then
        print_success "Pod就绪状态: $READY_STATUS"
    else
        print_warning "Pod就绪状态: $READY_STATUS"
    fi

    # 显示Pod详情
    print_info "Pod详情:"
    kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o wide

    # 显示事件
    print_info "最近事件:"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -5
}

# 测试Kubernetes连接
test_kubernetes_connection() {
    print_info "测试Pod内Kubernetes连接..."

    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$POD_NAME" ]]; then
        print_error "无法获取Pod名称"
        return 1
    fi

    print_info "测试Pod: $POD_NAME"

    # 等待Pod完全就绪
    sleep 10

    # 执行连接测试
    if kubectl exec -n $NAMESPACE $POD_NAME -- /home/runner/test-k8s.sh &> /dev/null; then
        print_success "Pod内Kubernetes连接测试通过"
    else
        print_warning "Pod内Kubernetes连接测试失败，检查Pod日志:"
        kubectl logs -n $NAMESPACE $POD_NAME --tail=20
    fi
}

# 显示部署信息
show_deployment_info() {
    print_info "部署信息:"
    echo "  📦 命名空间: $NAMESPACE"
    echo "  🚀 部署名称: $DEPLOYMENT_NAME"
    echo "  ⚙️  配置文件: $CONFIG_FILE"
    echo ""

    print_info "功能特性:"
    echo "  ✅ in-cluster Kubernetes通信"
    echo "  ✅ kubectl工具集成"
    echo "  ✅ Docker访问权限"
    echo "  ✅ 完整的CI/CD部署能力"
    echo ""

    print_info "可用命令:"
    echo "  📋 查看Pod: kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME"
    echo "  📝 查看日志: kubectl logs -n $NAMESPACE -l app=$DEPLOYMENT_NAME"
    echo "  🔍 连接测试: kubectl exec -n $NAMESPACE -l app=$DEPLOYMENT_NAME -- /home/runner/test-k8s.sh"
    echo ""

    print_info "清理命令:"
    echo "  🗑️  删除部署: kubectl delete -f $CONFIG_FILE"
}

# 主函数
main() {
    local action="${1:-deploy}"

    case "$action" in
        "deploy")
            echo "🚀 开始部署增强版GitHub Runner..."
            check_dependencies
            backup_existing
            deploy_enhanced_runner
            wait_for_deployment
            verify_deployment
            test_kubernetes_connection
            show_deployment_info
            print_success "增强版GitHub Runner部署完成！"
            ;;
        "verify")
            echo "🔍 验证增强版GitHub Runner部署..."
            verify_deployment
            test_kubernetes_connection
            show_deployment_info
            ;;
        "cleanup")
            echo "🗑️  清理增强版GitHub Runner..."
            if [[ -f "$CONFIG_FILE" ]]; then
                kubectl delete -f "$CONFIG_FILE"
                print_success "清理完成"
            else
                print_error "配置文件不存在: $CONFIG_FILE"
            fi
            ;;
        "status")
            echo "📊 查看增强版GitHub Runner状态..."
            verify_deployment
            ;;
        "logs")
            echo "📝 查看增强版GitHub Runner日志..."
            POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$POD_NAME" ]]; then
                kubectl logs -n $NAMESPACE $POD_NAME -f
            else
                print_error "无法找到Pod"
            fi
            ;;
        "help"|"-h"|"--help")
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  deploy   - 部署增强版Runner (默认)"
            echo "  verify   - 验证部署状态"
            echo "  cleanup  - 清理部署"
            echo "  status   - 查看部署状态"
            echo "  logs     - 查看Pod日志"
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