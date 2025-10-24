#!/bin/bash

# 精简版分支解析脚本
# 输出JSON格式，便于CI/CD处理

set -e

BRANCH_NAME="$1"

# 验证格式
if [[ ! "$BRANCH_NAME" =~ ^(develop|staging|prod)-(backend|frontend)-[a-zA-Z0-9-]+$ ]]; then
    echo "❌ 无效分支格式: $BRANCH_NAME"
    echo "正确格式: {environment}-{domain}-{app-name}"
    exit 1
fi

# 解析组件
ENVIRONMENT=$(echo "$BRANCH_NAME" | cut -d'-' -f1)
DOMAIN=$(echo "$BRANCH_NAME" | cut -d'-' -f2)
APP_NAME=$(echo "$BRANCH_NAME" | cut -d'-' -f3-)

# 应用配置映射
case "$DOMAIN" in
    "backend")
        APP_DIR="backend/app/${APP_NAME//-/_}"
        DOCKERFILE="backend/deploy/Dockerfile-first-app"
        SERVICE_NAME="${APP_NAME//-/_}"
        if [[ "$APP_NAME" == *"first"* ]]; then
            PORT="18080"
        elif [[ "$APP_NAME" == *"second"* ]]; then
            PORT="18081"
        else
            PORT="18080"
        fi
        ;;
    "frontend")
        APP_DIR="frontend/${APP_NAME//-/_}"
        DOCKERFILE=""
        SERVICE_NAME="${APP_NAME//-/_}"
        PORT="3000"
        ;;
    *)
        echo "❌ 不支持的域: $DOMAIN"
        exit 1
        ;;
esac

# 环境配置
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

# 其他配置
NAMESPACE="app-${ENVIRONMENT}"
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
IMAGE_NAME="${APP_NAME}-${ENVIRONMENT}"
IMAGE_TAG="${COMMIT_SHORT}"

# 输出JSON格式 (便于CI/CD处理)
cat <<EOF
{
  "environment": "$ENVIRONMENT",
  "domain": "$DOMAIN",
  "app_name": "$APP_NAME",
  "app_dir": "$APP_DIR",
  "dockerfile": "$DOCKERFILE",
  "service_name": "$SERVICE_NAME",
  "port": "$PORT",
  "namespace": "$NAMESPACE",
  "image_name": "$IMAGE_NAME",
  "image_tag": "$IMAGE_TAG",
  "log_level": "$LOG_LEVEL",
  "replicas": "$REPLICAS",
  "commit_short": "$COMMIT_SHORT"
}
EOF

# 如果在GitHub Actions中，也设置输出变量
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "environment=$ENVIRONMENT" >> $GITHUB_OUTPUT
    echo "domain=$DOMAIN" >> $GITHUB_OUTPUT
    echo "app_name=$APP_NAME" >> $GITHUB_OUTPUT
    echo "app_dir=$APP_DIR" >> $GITHUB_OUTPUT
    echo "dockerfile=$DOCKERFILE" >> $GITHUB_OUTPUT
    echo "service_name=$SERVICE_NAME" >> $GITHUB_OUTPUT
    echo "port=$PORT" >> $GITHUB_OUTPUT
    echo "namespace=$NAMESPACE" >> $GITHUB_OUTPUT
    echo "image_name=$IMAGE_NAME" >> $GITHUB_OUTPUT
    echo "image_tag=$IMAGE_TAG" >> $GITHUB_OUTPUT
    echo "log_level=$LOG_LEVEL" >> $GITHUB_OUTPUT
    echo "replicas=$REPLICAS" >> $GITHUB_OUTPUT
    echo "commit_short=$COMMIT_SHORT" >> $GITHUB_OUTPUT
fi