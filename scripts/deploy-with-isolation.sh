#!/bin/bash

# 带错误隔离的部署脚本
# 使用方法: ./scripts/deploy-with-isolation.sh [service] [environment] [image-tag]

set -e

# 获取参数
SERVICE="$1"
ENVIRONMENT="$2"
IMAGE_TAG="$3"

# 验证参数
if [[ -z "$SERVICE" || -z "$ENVIRONMENT" || -z "$IMAGE_TAG" ]]; then
    echo "❌ 错误: 缺少必需参数"
    echo "用法: $0 <service> <environment> <image-tag>"
    echo "示例: $0 first-app develop a1b2c3d"
    exit 1
fi

echo "🚀 开始部署 $SERVICE 到 $ENVIRONMENT 环境..."
echo "镜像标签: $IMAGE_TAG"

# 部署配置
NAMESPACE="app"
DEPLOYMENT_NAME="app-${SERVICE}-${ENVIRONMENT}"
K8S_CONFIG="k8s/local-dev-apps.yaml"
BACKUP_FILE="${K8S_CONFIG}.backup.$(date +%s)"

# 错误隔离函数
deploy_with_retry() {
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "🔄 部署尝试 $attempt/$max_attempts..."

        # 备份配置文件
        if [ -f "$K8S_CONFIG" ]; then
            cp "$K8S_CONFIG" "$BACKUP_FILE"
            echo "📋 配置文件已备份: $BACKUP_FILE"
        fi

        # 更新镜像标签
        echo "📝 更新镜像标签..."
        sed -i.bak "s|image: ${SERVICE}:PLACEHOLDER|image: ${SERVICE}:${IMAGE_TAG}|g" "$K8S_CONFIG"

        # 验证 K8s 集群连接
        if ! kubectl cluster-info &> /dev/null; then
            echo "❌ 无法连接到 Kubernetes 集群"
            restore_config
            return 1
        fi

        # 确保 namespace 存在
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

        # 部署应用
        echo "☸️ 部署到 Kubernetes..."
        if kubectl apply -f "$K8S_CONFIG"; then
            echo "✅ 配置应用成功"
        else
            echo "❌ 配置应用失败"
            restore_config
            return 1
        fi

        # 等待部署完成
        echo "⏳ 等待部署完成..."
        if kubectl rollout status deployment/"$DEPLOYMENT_NAME" --namespace="$NAMESPACE" --timeout=60s; then
            echo "✅ 部署成功"
            cleanup_backup
            return 0
        else
            echo "❌ 部署超时或失败"
            echo "🔄 回滚部署..."
            kubectl rollout undo deployment/"$DEPLOYMENT_NAME" --namespace="$NAMESPACE" || true

            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ 等待 10 秒后重试..."
                sleep 10
                restore_config
                ((attempt++))
            else
                echo "❌ 所有部署尝试都失败了"
                restore_config
                return 1
            fi
        fi
    done
}

# 恢复配置文件
restore_config() {
    if [ -f "${K8S_CONFIG}.bak" ]; then
        mv "${K8S_CONFIG}.bak" "$K8S_CONFIG"
        echo "🔄 配置文件已恢复"
    fi
}

# 清理备份文件
cleanup_backup() {
    if [ -f "${K8S_CONFIG}.bak" ]; then
        rm "${K8S_CONFIG}.bak"
    fi
    echo "🗑️ 清理临时文件"
}

# 健康检查函数
health_check() {
    echo "🧪 执行健康检查..."

    # 等待服务启动
    echo "⏳ 等待服务启动..."
    sleep 15

    # 根据服务类型进行不同的健康检查
    if [[ "$SERVICE" == *"app" ]]; then
        # 后端应用检查
        HEALTH_PATH="/${SERVICE%%-app}/ping"
        echo "检查: http://localhost$HEALTH_PATH"

        for i in {1..5}; do
            if curl -f "http://localhost$HEALTH_PATH" > /dev/null 2>&1; then
                echo "✅ 健康检查通过"
                return 0
            else
                echo "⏳ 健康检查尝试 $i/5 失败，等待 10 秒..."
                sleep 10
            fi
        done

        echo "⚠️ 健康检查失败，但部署可能仍在进行中"
        echo "📊 Pod 状态:"
        kubectl get pods --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT"
        return 1
    else
        # 前端应用检查
        echo "检查: http://localhost/health"

        for i in {1..5}; do
            if curl -f "http://localhost/health" > /dev/null 2>&1; then
                echo "✅ 健康检查通过"
                return 0
            else
                echo "⏳ 健康检查尝试 $i/5 失败，等待 10 秒..."
                sleep 10
            fi
        done

        echo "⚠️ 健康检查失败，但部署可能仍在进行中"
        return 1
    fi
}

# 验证部署状态
verify_deployment() {
    echo "📊 验证部署状态..."

    # 检查 Pod 状态
    echo "Pod 状态:"
    kubectl get pods --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT"

    # 检查服务状态
    echo "服务状态:"
    kubectl get services --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT"

    # 检查 Ingress 状态
    echo "Ingress 状态:"
    kubectl get ingressroutes --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT" || true
}

# 主执行流程
main() {
    # 执行部署
    if deploy_with_retry; then
        echo "✅ 部署成功!"

        # 验证部署
        verify_deployment

        # 健康检查
        health_check

        echo ""
        echo "🎉 部署流程完成!"
        echo "🌐 访问地址:"

        if [[ "$SERVICE" == *"app" ]]; then
            echo "  http://localhost/${SERVICE%%-app}/"
        else
            echo "  http://localhost/"
        fi

    else
        echo "❌ 部署失败!"
        echo "🔍 请检查以下信息:"
        echo "  1. 镜像是否正确构建: docker images | grep $SERVICE"
        echo "  2. K8s 集群是否正常: kubectl cluster-info"
        echo "  3. 配置文件是否正确: cat $K8S_CONFIG | grep $SERVICE"
        exit 1
    fi
}

# 错误处理
trap 'echo "❌ 脚本执行出错，正在清理..."; restore_config; cleanup_backup; exit 1' ERR

# 执行主函数
main "$@"