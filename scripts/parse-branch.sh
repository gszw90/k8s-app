#!/bin/bash

# 分支名称解析脚本
# 解析分支名称: {environment}-{domain}-{app-name}
# 示例: develop-backend-first-app → environment=develop, domain=backend, app-name=first-app

set -e

BRANCH_NAME="$1"

# 验证分支名称格式
if [[ ! "$BRANCH_NAME" =~ ^(develop|staging|prod)-(backend|frontend)-[a-zA-Z0-9-]+$ ]]; then
    echo "❌ 无效的分支名称格式: $BRANCH_NAME"
    echo "正确格式: {environment}-{domain}-{app-name}"
    echo "示例: develop-backend-first-app, staging-frontend-web-app, prod-backend-second-app"
    exit 1
fi

# 解析分支名称
ENVIRONMENT=$(echo "$BRANCH_NAME" | cut -d'-' -f1)
DOMAIN=$(echo "$BRANCH_NAME" | cut -d'-' -f2)
APP_NAME=$(echo "$BRANCH_NAME" | cut -d'-' -f3-)

# 映射到目录结构
if [ "$DOMAIN" = "backend" ]; then
    APP_DIR="backend/app/${APP_NAME//-/_}"
    DOCKERFILE="backend/deploy/Dockerfile-first-app"  # 统一使用现有的 Dockerfile
    SERVICE_NAME="${APP_NAME//-/_}"
    # 从应用名中提取端口号或使用默认值
    if [[ "$APP_NAME" == *"first"* ]]; then
        PORT="18080"
    elif [[ "$APP_NAME" == *"second"* ]]; then
        PORT="18081"
    else
        PORT="18080"
    fi
elif [ "$DOMAIN" = "frontend" ]; then
    APP_DIR="frontend/${APP_NAME//-/_}"
    DOCKERFILE=""  # Frontend 暂时不使用 Dockerfile
    SERVICE_NAME="${APP_NAME//-/_}"
    PORT="3000"
else
    echo "❌ 不支持的域: $DOMAIN"
    exit 1
fi

# Namespace 映射
NAMESPACE="app-${ENVIRONMENT}"

# 镜像标签配置
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
IMAGE_NAME="${APP_NAME}-${ENVIRONMENT}"
IMAGE_TAG="${COMMIT_SHORT}"

# 环境配置映射
case "$ENVIRONMENT" in
  "develop")
    LOG_LEVEL="DEBUG"
    REPLICAS="1"
    ;;
  "staging")
    LOG_LEVEL="INFO"
    REPLICAS="2"
    ;;
  "prod")
    LOG_LEVEL="WARN"
    REPLICAS="3"
    ;;
  *)
    LOG_LEVEL="INFO"
    REPLICAS="1"
    ;;
esac

# 输出解析结果
echo "📊 分支解析结果:"
echo "  环境: $ENVIRONMENT"
echo "  域: $DOMAIN"
echo "  应用名: $APP_NAME"
echo "  应用目录: $APP_DIR"
echo "  Dockerfile: $DOCKERFILE"
echo "  服务名: $SERVICE_NAME"
echo "  端口: $PORT"
echo "  Namespace: $NAMESPACE"
echo "  镜像名称: $IMAGE_NAME"
echo "  镜像标签: $IMAGE_TAG"
echo "  日志级别: $LOG_LEVEL"
echo "  副本数: $REPLICAS"
echo "  Commit: $COMMIT_SHORT"

# 输出环境变量（供 GitHub Actions 使用）
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "environment=$ENVIRONMENT" >> $GITHUB_OUTPUT
    echo "domain=$DOMAIN" >> $GITHUB_OUTPUT
    echo "app-name=$APP_NAME" >> $GITHUB_OUTPUT
    echo "app-dir=$APP_DIR" >> $GITHUB_OUTPUT
    echo "dockerfile=$DOCKERFILE" >> $GITHUB_OUTPUT
    echo "service-name=$SERVICE_NAME" >> $GITHUB_OUTPUT
    echo "port=$PORT" >> $GITHUB_OUTPUT
    echo "namespace=$NAMESPACE" >> $GITHUB_OUTPUT
    echo "image-name=$IMAGE_NAME" >> $GITHUB_OUTPUT
    echo "image-tag=$IMAGE_TAG" >> $GITHUB_OUTPUT
    echo "log-level=$LOG_LEVEL" >> $GITHUB_OUTPUT
    echo "replicas=$REPLICAS" >> $GITHUB_OUTPUT
    echo "commit-short=$COMMIT_SHORT" >> $GITHUB_OUTPUT
else
    echo "ℹ️ 本地运行模式 - GitHub Actions 输出跳过"
fi