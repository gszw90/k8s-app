#!/bin/bash

# 分支名称解析脚本
# 解析分支名称: {domain}-{app}-{environment}
# 示例: backend-first-app-develop → domain=backend, app=first-app, environment=develop

set -e

BRANCH_NAME="$1"

# 验证分支名称格式
if [[ ! "$BRANCH_NAME" =~ ^(backend|frontend)-[a-zA-Z0-9-]+-(develop|staging|prod)$ ]]; then
    echo "❌ 无效的分支名称格式: $BRANCH_NAME"
    echo "正确格式: {domain}-{app}-{environment}"
    echo "示例: backend-first-app-develop, frontend-web-app-staging"
    exit 1
fi

# 解析分支名称
DOMAIN=$(echo "$BRANCH_NAME" | cut -d'-' -f1)
TEMP_NAME=$(echo "$BRANCH_NAME" | cut -d'-' -f2-)

# 分离应用名和环境
if [[ "$TEMP_NAME" =~ ^(.*)-(develop|staging|prod)$ ]]; then
    APP_NAME="${BASH_REMATCH[1]}"
    ENVIRONMENT="${BASH_REMATCH[2]}"
else
    echo "❌ 无法解析应用名和环境: $TEMP_NAME"
    exit 1
fi

# 映射到目录结构
if [ "$DOMAIN" = "backend" ]; then
    APP_DIR="backend/app/${APP_NAME//-/_}"
    DOCKERFILE="docker/${APP_NAME}/Dockerfile.${ENVIRONMENT}"
    SERVICE_NAME="${APP_NAME}"
    PORT=$(echo "$APP_NAME" | grep -o '[0-9]\+' || echo "18080")
elif [ "$DOMAIN" = "frontend" ]; then
    APP_DIR="frontend/${APP_NAME//-/_}"
    DOCKERFILE="docker/${APP_NAME}/Dockerfile.${ENVIRONMENT}"
    SERVICE_NAME="${APP_NAME}"
    PORT="3000"
else
    echo "❌ 不支持的域: $DOMAIN"
    exit 1
fi

# 获取 Git short commit
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# 输出解析结果
echo "📊 分支解析结果:"
echo "  域: $DOMAIN"
echo "  应用名: $APP_NAME"
echo "  环境: $ENVIRONMENT"
echo "  应用目录: $APP_DIR"
echo "  Dockerfile: $DOCKERFILE"
echo "  服务名: $SERVICE_NAME"
echo "  端口: $PORT"
echo "  Commit: $COMMIT_SHORT"

# 输出环境变量（供 GitHub Actions 使用）
echo "::set-output name=domain::$DOMAIN"
echo "::set-output name=app-name::$APP_NAME"
echo "::set-output name=environment::$ENVIRONMENT"
echo "::set-output name=app-dir::$APP_DIR"
echo "::set-output name=dockerfile::$DOCKERFILE"
echo "::set-output name=service-name::$SERVICE_NAME"
echo "::set-output name=port::$PORT"
echo "::set-output name=commit-short::$COMMIT_SHORT"