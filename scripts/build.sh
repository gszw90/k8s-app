#!/bin/bash

# 统一构建脚本
# 使用方法: ./scripts/build.sh [environment] [service]
# 环境选项: develop, staging, prod
# 服务选项: first-app, second-app, web-app, all

set -e

# 获取参数
ENVIRONMENT=${1:-develop}
SERVICE=${2:-all}

# 验证环境参数
if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|prod)$ ]]; then
    echo "错误: 环境参数必须是 develop, staging 或 prod"
    exit 1
fi

# 验证服务参数
if [[ ! "$SERVICE" =~ ^(first-app|second-app|web-app|all)$ ]]; then
    echo "错误: 服务参数必须是 first-app, second-app, web-app 或 all"
    exit 1
fi

echo "🚀 开始构建 $SERVICE 的 $ENVIRONMENT 环境镜像..."

# 获取 Git commit hash 作为镜像标签
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="$COMMIT_SHA"

# 构建函数
build_service() {
    local service=$1
    local dockerfile="docker/$service/Dockerfile.$ENVIRONMENT"

    if [ ! -f "$dockerfile" ]; then
        echo "❌ Dockerfile 不存在: $dockerfile"
        return 1
    fi

    echo "📦 构建 $service:$IMAGE_TAG..."
    docker build -f "$dockerfile" -t "$service:$IMAGE_TAG" .

    # 创建环境标签用于快速识别
    ENV_TAG="$service:$ENVIRONMENT-latest"
    docker tag "$service:$IMAGE_TAG" "$ENV_TAG"

    echo "✅ $service 构建完成!"
    echo "   标签: $IMAGE_TAG, $ENV_TAG"
}

# 根据服务参数进行构建
case $SERVICE in
    "all")
        build_service "first-app"
        build_service "second-app"
        build_service "web-app"
        ;;
    *)
        build_service "$SERVICE"
        ;;
esac

echo ""
echo "🎉 构建完成!"
echo "📋 构建的镜像:"
docker images | grep -E "(first-app|second-app|web-app)" | grep "$IMAGE_TAG" || true

echo ""
echo "🚀 部署命令:"
echo "  开发环境: docker-compose -f docker-compose/develop.yaml up -d"
echo "  预发布: docker-compose -f docker-compose/staging.yaml up -d"
echo "  生产: docker-compose -f docker-compose/prod.yaml up -d"