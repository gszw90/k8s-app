#!/bin/bash

# K8s 部署脚本 - 用于部署应用到 Kubernetes
# 使用方法: ./deploy-to-k8s.sh [environment]

set -e

# 设置环境变量
ENVIRONMENT=${1:-develop}
NAMESPACE="app"
PROJECT_ROOT=$(cd ../../.. && pwd)

echo "🚀 Deploying to Kubernetes..."
echo "Environment: $ENVIRONMENT"
echo "Namespace: $NAMESPACE"
echo "Project root: $PROJECT_ROOT"

# 检查 kubectl 是否可用
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# 检查集群连接
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

# 创建 namespace（如果不存在）
echo "📦 Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 应用基础配置（namespace, configmap, middlewares）
echo "⚙️ Applying base configurations..."
kubectl apply -f $PROJECT_ROOT/backend/deploy/k8s/namespace.yaml

# 部署 Backend Services
echo "🔧 Deploying backend services..."
kubectl apply -f $PROJECT_ROOT/backend/deploy/k8s/first-app-deployment.yaml
kubectl apply -f $PROJECT_ROOT/backend/deploy/k8s/second-app-deployment.yaml

# 部署 Frontend Services
echo "🎨 Deploying frontend services..."
kubectl apply -f $PROJECT_ROOT/frontend/first_app/deploy/k8s/web-deployment.yaml

# 等待部署完成
echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=60s \
    deployment/app-first-app-develop \
    deployment/app-second-app-develop \
    deployment/app-web-develop \
    -n $NAMESPACE

# 显示部署状态
echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "📊 Deployment status:"
kubectl get pods -n $NAMESPACE -l environment=$ENVIRONMENT

echo ""
echo "🌐 Service URLs:"
echo "  - First App: http://first-app-develop.localhost"
echo "  - Second App: http://second-app-develop.localhost"
echo "  - Web App: http://web-develop.localhost"

echo ""
echo "🔍 Check logs:"
echo "  kubectl logs -n $NAMESPACE deployment/app-first-app-develop"
echo "  kubectl logs -n $NAMESPACE deployment/app-web-develop"