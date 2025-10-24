#!/bin/bash

# Actions Runner Controller (ARC) 部署脚本
# 使用GitHub App认证，替代现有的手动runner管理

set -e

echo "🚀 部署Actions Runner Controller (ARC)"
echo "=================================="

# 配置变量
GITHUB_APP_ID="2168366"
GITHUB_APP_INSTALLATION_ID="91349326"
PRIVATE_KEY_FILE="./config/github-app-private-key.pem"
ARC_NAMESPACE="actions-runner-system"

# 检查依赖
check_dependencies() {
    echo "🔍 检查依赖..."

    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl未安装"
        exit 1
    fi

    # 检查helm
    if ! command -v helm &> /dev/null; then
        echo "❌ helm未安装"
        exit 1
    fi

    # 检查私钥文件
    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        echo "❌ GitHub App私钥文件不存在: $PRIVATE_KEY_FILE"
        exit 1
    fi

    echo "✅ 所有依赖检查通过"
}

# 检查当前集群状态
check_cluster_status() {
    echo "🔍 检查Kubernetes集群状态..."

    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ 无法连接到Kubernetes集群"
        exit 1
    fi

    echo "✅ Kubernetes集群连接正常"
    kubectl cluster-info
}

# 创建命名空间
create_namespace() {
    echo "🏷️ 创建ARC命名空间..."

    if kubectl get namespace "$ARC_NAMESPACE" &> /dev/null; then
        echo "✅ 命名空间 $ARC_NAMESPACE 已存在"
    else
        kubectl create namespace "$ARC_NAMESPACE"
        echo "✅ 命名空间 $ARC_NAMESPACE 创建成功"
    fi
}

# 创建GitHub App认证secret
create_github_app_secret() {
    echo "🔑 创建GitHub App认证secret..."

    # 检查是否已存在
    if kubectl get secret controller-manager -n "$ARC_NAMESPACE" &> /dev/null; then
        echo "ℹ️  Secret已存在，删除重建..."
        kubectl delete secret controller-manager -n "$ARC_NAMESPACE"
    fi

    # 创建secret
    kubectl create secret generic controller-manager \
        -n "$ARC_NAMESPACE" \
        --from-literal=github_app_id="$GITHUB_APP_ID" \
        --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
        --from-file=github_app_private_key="$PRIVATE_KEY_FILE"

    echo "✅ GitHub App认证secret创建成功"

    # 验证secret
    echo "📋 Secret详情:"
    kubectl get secret controller-manager -n "$ARC_NAMESPACE" -o yaml
}

# 添加Helm仓库
add_helm_repo() {
    echo "📦 添加ARC Helm仓库..."

    if helm repo list | grep -q "actions-runner-controller"; then
        echo "ℹ️  Helm仓库已存在，更新..."
        helm repo update actions-runner-controller
    else
        helm repo add actions-runner-controller \
            https://actions-runner-controller.github.io/actions-runner-controller
        helm repo update
    fi

    echo "✅ Helm仓库配置完成"
}

# 部署ARC Controller
deploy_arc_controller() {
    echo "🚀 部署ARC Controller..."

    # 检查现有部署
    if helm list -n "$ARC_NAMESPACE" | grep -q "actions-runner-controller"; then
        echo "ℹ️  ARC Controller已存在，升级..."
        helm upgrade actions-runner-controller \
            actions-runner-controller/actions-runner-controller \
            --namespace "$ARC_NAMESPACE" \
            --set authSecret.create=false \
            --set authSecret.name=controller-manager \
            --set=githubWebhookServer.enabled=false \
            --wait
    else
        echo "🔄 首次部署ARC Controller..."
        helm install actions-runner-controller \
            actions-runner-controller/actions-runner-controller \
            --namespace "$ARC_NAMESPACE" \
            --set authSecret.create=false \
            --set authSecret.name=controller-manager \
            --set=githubWebhookServer.enabled=false \
            --wait
    fi

    echo "✅ ARC Controller部署成功"
}

# 验证部署状态
verify_deployment() {
    echo "🔍 验证ARC Controller部署状态..."

    # 等待pod就绪
    echo "⏳ 等待Controller Manager pod就绪..."
    kubectl wait --for=condition=available \
        deployment/controller-manager \
        -n "$ARC_NAMESPACE" \
        --timeout=300s

    # 检查pod状态
    echo "📊 Controller Manager pod状态:"
    kubectl get pods -n "$ARC_NAMESPACE" -l app.kubernetes.io/name=actions-runner-controller

    # 检查CRD是否注册
    echo "📋 检查CRD资源..."
    kubectl get crd | grep actions.summerwind.dev || echo "⚠️  CRD尚未完全注册，请稍等片刻"

    echo "✅ 部署验证完成"
}

# 创建多环境命名空间
create_environment_namespaces() {
    echo "🏷️ 创建多环境命名空间..."

    environments=("github-runners-develop" "github-runners-staging" "github-runners-prod")

    for env in "${environments[@]}"; do
        if kubectl get namespace "$env" &> /dev/null; then
            echo "✅ 命名空间 $env 已存在"
        else
            kubectl create namespace "$env"
            echo "✅ 命名空间 $env 创建成功"
        fi
    done
}

# 显示下一步操作
show_next_steps() {
    echo ""
    echo "🎯 ARC Controller部署完成！"
    echo "=================================="
    echo ""
    echo "📋 下一步操作："
    echo "1. 创建RunnerDeployment资源"
    echo "2. 配置HorizontalRunnerAutoscaler"
    echo "3. 更新GitHub Actions workflow"
    echo "4. 测试CI/CD流水线"
    echo ""
    echo "🔧 有用的命令："
    echo "- 查看ARC日志: kubectl logs -f deployment/controller-manager -n $ARC_NAMESPACE"
    echo "- 查看runner状态: kubectl get runners -A"
    echo "- 查看runner部署: kubectl get runnerdeployments -A"
    echo ""
    echo "📚 相关脚本："
    echo "- 创建Runner资源: ./scripts/create-arc-runners.sh"
    echo "- 清理ARC: ./scripts/cleanup-arc.sh"
}

# 主函数
main() {
    echo "开始部署Actions Runner Controller..."
    echo ""

    check_dependencies
    check_cluster_status
    create_namespace
    create_github_app_secret
    add_helm_repo
    deploy_arc_controller
    verify_deployment
    create_environment_namespaces
    show_next_steps

    echo ""
    echo "🎉 ARC Controller部署成功完成！"
}

# 执行主函数
main "$@"