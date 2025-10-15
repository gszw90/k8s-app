#!/bin/bash

# 清理脚本 - 删除所有部署的资源
# 使用方法: ./scripts/cleanup.sh [--force]

set -e

# 获取参数
FORCE_CLEANUP=${1:-false}

echo "🧹 开始清理部署资源..."

# 清理函数
cleanup_namespace() {
    local namespace=$1
    local confirmation=$2

    if [ "$FORCE_CLEANUP" != "--force" ]; then
        echo "⚠️  即将删除 namespace: $namespace"
        echo "这将会删除该 namespace 下的所有资源!"
        read -p "确认删除? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过删除 $namespace"
            return 0
        fi
    fi

    if kubectl get namespace "$namespace" > /dev/null 2>&1; then
        echo "🗑️ 删除 namespace: $namespace"
        kubectl delete namespace "$namespace" --timeout=120s
        echo "✅ $namespace 删除完成!"
    else
        echo "ℹ️ namespace $namespace 不存在，跳过"
    fi
}

# 清理 Docker 镜像
cleanup_docker_images() {
    echo "🐳 清理 Docker 镜像..."

    # 删除悬空镜像
    docker image prune -f

    # 删除项目相关镜像
    local images_to_remove=$(docker images | grep -E "(first-app|second-app|web-app)" | awk '{print $1":"$2}')
    if [ -n "$images_to_remove" ]; then
        echo "删除以下镜像:"
        echo "$images_to_remove"
        docker rmi $images_to_remove 2>/dev/null || true
    fi

    echo "✅ Docker 镜像清理完成!"
}

# 清理 K8s 资源
echo "☸️ 清理 Kubernetes 资源..."
cleanup_namespace "backend-first-app"
cleanup_namespace "backend-second-app"
cleanup_namespace "frontend-web-app"
cleanup_namespace "app"  # 清理旧的 namespace

# 清理 Docker 资源
cleanup_docker_images

# 清理临时文件
echo "🗂️ 清理临时文件..."
find . -name "*.bak" -delete
find . -name "*.tmp" -delete
echo "✅ 临时文件清理完成!"

# 清理 Docker Compose
echo "🐳 停止所有 Docker Compose 服务..."
docker-compose -f docker-compose/develop.yaml down --remove-orphans 2>/dev/null || true
docker-compose -f docker-compose/staging.yaml down --remove-orphans 2>/dev/null || true
docker-compose -f docker-compose/prod.yaml down --remove-orphans 2>/dev/null || true
echo "✅ Docker Compose 清理完成!"

echo ""
echo "🎉 清理完成!"
echo "💡 提示: 使用 --force 参数可以跳过确认直接清理"