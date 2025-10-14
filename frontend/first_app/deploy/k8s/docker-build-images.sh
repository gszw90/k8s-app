#!/bin/bash

# 构建脚本 - 用于构建所有应用的 Docker 镜像
# 使用方法: ./docker-build-images.sh [git-commit-hash]

set -e

# 获取 Git short commit hash 或使用传入参数
COMMIT_SHA=${1:-$(git rev-parse --short HEAD)}
echo "Building images with Git commit: $COMMIT_SHA"

# 构建 Backend First App
echo "Building backend first-app..."
cd backend/app/first_app
docker build -t first-app:$COMMIT_SHA .
docker tag first-app:$COMMIT_SHA first-app:latest

# 构建 Backend Second App
echo "Building backend second-app..."
cd ../second_app
docker build -t second-app:$COMMIT_SHA .
docker tag second-app:$COMMIT_SHA second-app:latest

# 构建 Frontend Web App
echo "Building frontend web-app..."
cd ../../../../frontend/first_app
docker build -t web-app:$COMMIT_SHA .
docker tag web-app:$COMMIT_SHA web-app:latest

echo "✅ All images built successfully!"
echo "Images created:"
echo "  - first-app:$COMMIT_SHA"
echo "  - second-app:$COMMIT_SHA"
echo "  - web-app:$COMMIT_SHA"

# 显示本地镜像列表
echo ""
echo "📋 Local Docker images:"
docker images | grep -E "(first-app|second-app|web-app)" | head -10