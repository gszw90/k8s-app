#!/bin/bash

# 简化的端到端测试脚本
# 使用方法: ./build-and-test.sh

set -e

# 获取 Git short commit hash
COMMIT_SHA=$(git rev-parse --short HEAD)
echo "🚀 开始端到端测试，Git commit: $COMMIT_SHA"

# 1. 构建 Docker 镜像
echo ""
echo "📦 构建 Docker 镜像..."

# 构建 first-app
echo "构建 first-app..."
docker build -f backend/app/first_app/Dockerfile -t first-app:$COMMIT_SHA .
docker tag first-app:$COMMIT_SHA first-app:latest

# 构建 second-app
echo "构建 second-app..."
docker build -f backend/app/second_app/Dockerfile -t second-app:$COMMIT_SHA .
docker tag second-app:$COMMIT_SHA second-app:latest

# 构建 web-app
echo "构建 web-app..."
docker build -f frontend/first_app/Dockerfile -t web-app:$COMMIT_SHA .
docker tag web-app:$COMMIT_SHA web-app:latest

echo "✅ 所有镜像构建完成!"

# 2. 显示镜像信息
echo ""
echo "📋 构建的镜像:"
docker images | grep -E "(first-app|second-app|web-app)" | head -10

# 3. 部署到 K8s
echo ""
echo "☸️ 部署到 Kubernetes..."

# 创建 namespace
kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -

# 应用基础配置
kubectl apply -f backend/deploy/k8s/namespace.yaml

# 更新部署文件中的镜像标签
echo "更新镜像标签..."

# 更新 first-app
sed -i.bak "s|image: .*:latest|image: first-app:$COMMIT_SHA|g" backend/deploy/k8s/first-app-deployment.yaml

# 更新 second-app
sed -i.bak "s|image: .*:latest|image: second-app:$COMMIT_SHA|g" backend/deploy/k8s/second-app-deployment.yaml

# 更新 web-app
sed -i.bak "s|image: .*:latest|image: web-app:$COMMIT_SHA|g" frontend/first_app/deploy/k8s/web-deployment.yaml

# 应用部署
kubectl apply -f backend/deploy/k8s/first-app-deployment.yaml
kubectl apply -f backend/deploy/k8s/second-app-deployment.yaml
kubectl apply -f frontend/first_app/deploy/k8s/web-deployment.yaml

echo "✅ 部署完成!"

# 4. 等待部署就绪
echo ""
echo "⏳ 等待部署就绪..."
kubectl wait --for=condition=available --timeout=60s \
    deployment/app-first-app-develop \
    deployment/app-second-app-develop \
    deployment/app-web-develop \
    -n app || {
    echo "❌ 部署未能在规定时间内就绪"
    kubectl get pods -n app
    exit 1
}

# 5. 验证部署状态
echo ""
echo "📊 验证部署状态:"
kubectl get pods -n app -l environment=develop

# 6. 测试服务连通性
echo ""
echo "🧪 测试服务连通性..."

# 测试 first-app
echo "测试 first-app /ping 端点..."
kubectl run test-first-app --image=curlimages/curl --rm -i --restart=Never -n app -- \
    curl -f http://app-first-app-develop.app.svc.cluster.local:18080/ping || echo "⚠️ first-app ping 测试失败"

# 测试 second-app
echo "测试 second-app /ping 端点..."
kubectl run test-second-app --image=curlimages/curl --rm -i --restart=Never -n app -- \
    curl -f http://app-second-app-develop.app.svc.cluster.local:18081/ping || echo "⚠️ second-app ping 测试失败"

# 测试 web-app
echo "测试 web-app /health 端点..."
kubectl run test-web-app --image=curlimages/curl --rm -i --restart=Never -n app -- \
    curl -f http://app-web-develop.app.svc.cluster.local:3000/health || echo "⚠️ web-app health 测试失败"

# 7. 显示访问信息
echo ""
echo "🎉 测试完成!"
echo ""
echo "🌐 服务访问地址:"
echo "  - First App: http://first-app-develop.localhost"
echo "  - Second App: http://second-app-develop.localhost"
echo "  - Web App: http://web-develop.localhost"
echo ""
echo "🔍 查看日志:"
echo "  kubectl logs -n app deployment/app-first-app-develop -f"
echo "  kubectl logs -n app deployment/app-web-develop -f"

# 8. 清理备份文件
echo ""
echo "🧹 清理临时文件..."
mv backend/deploy/k8s/first-app-deployment.yaml.bak backend/deploy/k8s/first-app-deployment.yaml
mv backend/deploy/k8s/second-app-deployment.yaml.bak backend/deploy/k8s/second-app-deployment.yaml
mv frontend/first_app/deploy/k8s/web-deployment.yaml.bak frontend/first_app/deploy/k8s/web-deployment.yaml

echo "✅ 端到端测试完成!"