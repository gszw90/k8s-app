#!/bin/bash

# GitHub Runner 管理脚本
# 用法: ./github-runner-manager.sh [command]

set -e

NAMESPACE="github-runners"
DEPLOYMENT_NAME="github-runner"

# 显示使用说明
show_usage() {
    echo "GitHub Runner 管理脚本"
    echo "======================"
    echo "用法: $0 [command]"
    echo ""
    echo "可用命令:"
    echo "  deploy     部署 GitHub Runner"
    echo "  status     查看部署状态"
    echo "  logs       查看 Runner 日志"
    echo "  restart    重启 Runner"
    echo "  scale      扩展/缩减 Runner 数量"
    echo "  cleanup    清理所有资源"
    echo "  help       显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 deploy"
    echo "  $0 status"
    echo "  $0 logs"
    echo "  $0 restart"
    echo "  $0 scale 3"
    echo "  $0 cleanup"
}

# 检查 kubectl 是否可用
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl 命令未找到，请先安装 kubectl"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ 无法连接到 Kubernetes 集群"
        exit 1
    fi
}

# 部署 GitHub Runner
deploy_runner() {
    echo "🚀 开始部署 GitHub Runner..."

    # 检查配置文件是否存在
    if [ ! -d "k8s/github-runners" ]; then
        echo "❌ 配置文件目录不存在: k8s/github-runners"
        exit 1
    fi

    # 按顺序部署资源
    echo "📦 创建 namespace..."
    kubectl apply -f k8s/github-runners/namespace.yaml

    echo "⚙️ 创建配置..."
    kubectl apply -f k8s/github-runners/configmap.yaml
    kubectl apply -f k8s/github-runners/secret.yaml

    echo "🔐 创建 RBAC 权限..."
    kubectl apply -f k8s/github-runners/rbac.yaml

    echo "🚀 部署 Runner..."
    kubectl apply -f k8s/github-runners/deployment.yaml

    echo "✅ GitHub Runner 部署完成！"
    echo ""
    echo "📊 使用以下命令查看状态:"
    echo "  $0 status"
    echo "  $0 logs"
}

# 查看部署状态
show_status() {
    echo "📊 GitHub Runner 状态"
    echo "=================="
    echo ""

    # 显示命名空间信息
    echo "🏷️ Namespace:"
    kubectl get namespace $NAMESPACE 2>/dev/null || echo "  ❌ Namespace 不存在"
    echo ""

    # 显示 Pod 状态
    echo "🏷️ Pods:"
    kubectl get pods -n $NAMESPACE -o wide 2>/dev/null || echo "  ❌ 无 Pods"
    echo ""

    # 显示 Deployment 状态
    echo "🚀 Deployments:"
    kubectl get deployments -n $NAMESPACE 2>/dev/null || echo "  ❌ 无 Deployments"
    echo ""

    # 显示 ServiceAccount 状态
    echo "👤 ServiceAccounts:"
    kubectl get serviceaccounts -n $NAMESPACE 2>/dev/null || echo "  ❌ 无 ServiceAccounts"
    echo ""

    # 显示最近事件
    echo "📋 最近事件:"
    kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -5 2>/dev/null || echo "  ❌ 无事件"
}

# 查看日志
show_logs() {
    echo "📋 GitHub Runner 日志"
    echo "==================="
    echo ""

    # 获取 Pod 名称
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=github-runner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$POD_NAME" ]; then
        echo "❌ 未找到运行中的 Runner Pod"
        exit 1
    fi

    echo "📝 Pod: $POD_NAME"
    echo ""

    # 显示日志
    kubectl logs -n $NAMESPACE -f $POD_NAME
}

# 重启 Runner
restart_runner() {
    echo "🔄 重启 GitHub Runner..."

    # 重启 Deployment
    kubectl rollout restart deployment/$DEPLOYMENT_NAME -n $NAMESPACE

    echo "⏳ 等待重启完成..."
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=120s

    echo "✅ Runner 重启完成"
}

# 扩展/缩减 Runner 数量
scale_runner() {
    if [ -z "$1" ]; then
        echo "❌ 请指定副本数量"
        echo "用法: $0 scale <replicas>"
        exit 1
    fi

    REPLICAS="$1"

    if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]]; then
        echo "❌ 副本数量必须是数字"
        exit 1
    fi

    echo "📈 调整 Runner 副本数量到 $REPLICAS..."

    kubectl scale deployment/$DEPLOYMENT_NAME -n $NAMESPACE --replicas=$REPLICAS

    echo "⏳ 等待扩缩容完成..."
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=120s

    echo "✅ 副本数量调整完成"
}

# 清理所有资源
cleanup_resources() {
    echo "🧹 清理 GitHub Runner 资源..."
    echo "⚠️  这将删除所有相关资源，确定要继续吗？"
    read -p "输入 'yes' 确认: " confirm

    if [ "$confirm" != "yes" ]; then
        echo "❌ 操作已取消"
        exit 0
    fi

    echo "🗑️  删除部署资源..."
    kubectl delete -f k8s/github-runners/deployment.yaml 2>/dev/null || true
    kubectl delete -f k8s/github-runners/rbac.yaml 2>/dev/null || true
    kubectl delete -f k8s/github-runners/secret.yaml 2>/dev/null || true
    kubectl delete -f k8s/github-runners/configmap.yaml 2>/dev/null || true
    kubectl delete -f k8s/github-runners/namespace.yaml 2>/dev/null || true

    echo "✅ 清理完成"
}

# 主程序
main() {
    case "${1:-help}" in
        "deploy")
            check_kubectl
            deploy_runner
            ;;
        "status")
            check_kubectl
            show_status
            ;;
        "logs")
            check_kubectl
            show_logs
            ;;
        "restart")
            check_kubectl
            restart_runner
            ;;
        "scale")
            check_kubectl
            scale_runner "$2"
            ;;
        "cleanup")
            check_kubectl
            cleanup_resources
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 执行主程序
main "$@"