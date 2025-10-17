#!/bin/bash

# Kubernetes 部署脚本
# 使用方法: ./scripts/deploy.sh [app-name] [environment]
# 示例: ./scripts/deploy.sh first-app develop

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取参数
APP_NAME=${1:-first-app}
ENVIRONMENT=${2:-develop}

# 应用配置映射
declare -A APP_CONFIGS=(
    ["first-app"]="deploy/k8s/backend-first-app.yaml:backend-first-app"
    ["second-app"]="deploy/k8s/backend-second-app.yaml:backend-second-app"
    ["web-app"]="deploy/k8s/frontend-web-app.yaml:frontend-web-app"
)

# 验证应用参数
if [[ -z "${APP_CONFIGS[$APP_NAME]}" ]]; then
    echo -e "${RED}❌ 错误: 未知的应用 '$APP_NAME'${NC}"
    echo -e "${YELLOW}可用应用: first-app, second-app, web-app${NC}"
    exit 1
fi

# 验证环境参数
if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|prod)$ ]]; then
    echo -e "${RED}❌ 错误: 环境参数必须是 develop, staging 或 prod${NC}"
    exit 1
fi

# 解析应用配置
CONFIG_PATH=$(echo "${APP_CONFIGS[$APP_NAME]}" | cut -d: -f1)
NAMESPACE=$(echo "${APP_CONFIGS[$APP_NAME]}" | cut -d: -f2)

echo -e "${BLUE}🚀 开始部署应用: $APP_NAME${NC}"
echo -e "${BLUE}域: ${NAMESPACE%%-*}${NC}"
echo -e "${BLUE}环境: $ENVIRONMENT${NC}"
echo -e "${BLUE}命名空间: $NAMESPACE${NC}"

# 获取 Git commit hash
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="$COMMIT_SHA"

echo -e "${BLUE}镜像标签: $IMAGE_TAG${NC}"

# 检查并安装kubectl
check_install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${BLUE}📦 kubectl 未安装，正在安装...${NC}"
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        echo -e "${GREEN}✅ kubectl 安装完成${NC}"
    fi
}

# 配置KUBECONFIG
setup_kubeconfig() {
    if [[ -z "$KUBECONFIG" ]]; then
        # 在GitHub Actions环境中，需要设置KUBECONFIG
        if [[ -n "$GITHUB_ACTIONS" ]]; then
            # 检查是否有配置文件被设置在环境中
            if [[ -n "$KUBE_CONFIG_DATA" ]]; then
                echo -e "${BLUE}🔧 设置GitHub Actions的KUBECONFIG...${NC}"
                mkdir -p ~/.kube
                echo "$KUBE_CONFIG_DATA" | base64 -d > ~/.kube/config
                export KUBECONFIG="$HOME/.kube/config"
            else
                echo -e "${YELLOW}⚠️ 警告: GitHub Actions环境中未设置KUBE_CONFIG_DATA${NC}"
                echo -e "${YELLOW}⚠️ 将尝试使用in-cluster配置${NC}"
            fi
        else
            # 本地环境，使用默认配置
            export KUBECONFIG="$HOME/.kube/config"
        fi
    fi
}

# 验证集群连接
verify_cluster_connection() {
    echo -e "${BLUE}🔍 验证集群连接...${NC}"

    # 检查kubectl是否可用
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ 无法连接到 Kubernetes 集群${NC}"
        echo -e "${YELLOW}🔍 集群诊断信息:${NC}"
        echo -e "${YELLOW}  当前用户: $(whoami)${NC}"
        echo -e "${YELLOW}  KUBECONFIG: ${KUBECONFIG:-'未设置'}${NC}"
        echo -e "${YELLOW}  kubectl版本: $(kubectl version --client --short 2>/dev/null || echo '未知')${NC}"

        # 显示可用的contexts（如果有配置文件）
        if [[ -f "$HOME/.kube/config" ]]; then
            echo -e "${YELLOW}  可用的contexts: $(kubectl config get-contexts -o name 2>/dev/null || echo '无')${NC}"
        fi

        return 1
    fi

    echo -e "${GREEN}✅ 集群连接正常${NC}"
    return 0
}

# 创建命名空间（如果不存在）
create_namespace() {
    local namespace=$1
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        echo -e "${BLUE}📝 创建命名空间: $namespace${NC}"
        kubectl create namespace "$namespace"
    else
        echo -e "${BLUE}✅ 命名空间已存在: $namespace${NC}"
    fi
}

# 部署函数
deploy_k8s() {
    local config_file=$1
    local namespace=$2

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ 配置文件不存在: $config_file${NC}"
        return 1
    fi

    echo -e "${BLUE}☸️ 部署 $config_file 到 $namespace...${NC}"

    # 创建命名空间
    create_namespace "$namespace"

    # 设置环境变量
    export NAMESPACE="$namespace"
    export ENVIRONMENT="$ENVIRONMENT"
    export APP_NAME="$APP_NAME"
    export IMAGE_TAG="$IMAGE_TAG"
    export DOMAIN="${NAMESPACE%%-*}"
    export PORT="${PORT:-18080}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    export REPLICAS="${REPLICAS:-1}"
    export DB_PASSWORD="$(echo -n 'default-password' | base64)"
    export API_KEY="$(echo -n 'default-api-key' | base64)"
    export SESSION_SECRET="$(echo -n 'default-session-secret' | base64)"

    # 根据应用名称更新镜像标签
    case "$APP_NAME" in
        "first-app"|"second-app")
            export FULL_IMAGE_NAME="$APP_NAME:$IMAGE_TAG"
            ;;
        "web-app")
            export FULL_IMAGE_NAME="$APP_NAME:$IMAGE_TAG"
            ;;
    esac

    # 使用envsubst替换配置文件中的变量
    echo -e "${BLUE}🔄 替换配置文件变量...${NC}"
    envsubst < "$config_file" > "/tmp/${APP_NAME}-config.yaml"

    # 验证替换后的配置文件
    echo -e "${BLUE}📋 验证配置文件...${NC}"
    if ! kubectl apply --dry-run=client -f "/tmp/${APP_NAME}-config.yaml"; then
        echo -e "${RED}❌ 配置文件验证失败${NC}"
        return 1
    fi

    # 应用配置
    kubectl apply -f "/tmp/${APP_NAME}-config.yaml"

    # 等待部署完成
    echo -e "${BLUE}⏳ 等待部署完成...${NC}"
    DEPLOYMENT_NAME="${DOMAIN}-${APP_NAME}"
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" --namespace="$namespace" --timeout=300s

    # 清理临时文件
    rm -f "/tmp/${APP_NAME}-config.yaml"

    echo -e "${GREEN}✅ $config_file 部署完成!${NC}"
}

# 主执行流程
main() {
    # 检查并安装kubectl
    check_install_kubectl

    # 配置KUBECONFIG
    setup_kubeconfig

    # 验证集群连接
    if ! verify_cluster_connection; then
        echo -e "${RED}❌ 集群连接失败，无法继续部署${NC}"
        exit 1
    fi

    # 执行部署
    deploy_k8s "$CONFIG_PATH" "$NAMESPACE"

    # 验证部署
    echo ""
    echo -e "${GREEN}📊 验证部署状态:${NC}"
    kubectl get pods --namespace="$NAMESPACE" --selector=app="$APP_NAME"

    echo ""
    echo -e "${GREEN}🌐 服务访问地址:${NC}"
    echo -e "${GREEN}  $APP_NAME $ENVIRONMENT: http://$APP_NAME-$ENVIRONMENT.localhost${NC}"

    echo ""
    echo -e "${BLUE}🔍 查看日志:${NC}"
    echo -e "${BLUE}  kubectl logs -n $NAMESPACE deployment/$APP_NAME -f${NC}"

    echo ""
    echo -e "${GREEN}🎉 部署完成!${NC}"
}

# 执行主函数
main