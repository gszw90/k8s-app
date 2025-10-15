#!/bin/bash

# Kubernetes 部署脚本
# 使用方法: ./scripts/deploy.sh [environment] [namespace]
# 环境选项: develop, staging, prod

set -e

# 获取参数
ENVIRONMENT=${1:-develop}
NAMESPACE=${2:-backend-first-app}

# 验证环境参数
if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|prod)$ ]]; then
    echo "错误: 环境参数必须是 develop, staging 或 prod"
    exit 1
fi

echo "🚀 开始部署到 $ENVIRONMENT 环境..."

# 获取 Git commit hash
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="$COMMIT_SHA-$ENVIRONMENT"

# 部署函数
deploy_k8s() {
    local config_file=$1
    local namespace=$2

    if [ ! -f "$config_file" ]; then
        echo "❌ 配置文件不存在: $config_file"
        return 1
    fi

    echo "☸️ 部署 $config_file 到 $namespace..."

    # 更新镜像标签
    sed -i.bak "s|image: .*:develop|image: first-app:$IMAGE_TAG|g" "$config_file"
    sed -i.bak "s|image: .*:staging|image: first-app:$IMAGE_TAG|g" "$config_file"
    sed -i.bak "s|image: .*:prod|image: first-app:$IMAGE_TAG|g" "$config_file"

    # 应用配置
    kubectl apply -f "$config_file"

    # 等待部署完成
    echo "⏳ 等待部署完成..."
    kubectl rollout status deployment/* --namespace="$namespace" --timeout=300s

    # 恢复备份文件
    mv "$config_file.bak" "$config_file"

    echo "✅ $config_file 部署完成!"
}

# 部署后端服务
echo "📦 部署后端服务..."
deploy_k8s "k8s/backend-first-app.yaml" "backend-first-app"
deploy_k8s "k8s/backend-second-app.yaml" "backend-second-app"

# 部署前端服务
echo "📦 部署前端服务..."
deploy_k8s "k8s/frontend-web-app.yaml" "frontend-web-app"

# 验证部署
echo ""
echo "📊 验证部署状态:"
kubectl get pods --all-namespaces | grep -E "(backend-first-app|backend-second-app|frontend-web-app)"

echo ""
echo "🌐 服务访问地址:"
echo "  First App $ENVIRONMENT: http://first-app-$ENVIRONMENT.localhost"
echo "  Second App $ENVIRONMENT: http://second-app-$ENVIRONMENT.localhost"
echo "  Web App $ENVIRONMENT: http://web-$ENVIRONMENT.localhost"

echo ""
echo "🔍 查看日志:"
echo "  kubectl logs -n backend-first-app deployment/first-app-$ENVIRONMENT -f"
echo "  kubectl logs -n backend-second-app deployment/second-app-$ENVIRONMENT -f"
echo "  kubectl logs -n frontend-web-app deployment/web-app-$ENVIRONMENT -f"

echo ""
echo "🎉 部署完成!"