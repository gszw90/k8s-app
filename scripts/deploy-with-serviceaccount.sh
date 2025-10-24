#!/bin/bash

# 使用Kubernetes ServiceAccount认证的部署脚本
# 解决GitHub Actions在K8s pod中运行时的权限问题

set -e

# 配置
NAMESPACE="${1:-app-develop}"
APP_NAME="${2:-first-app}"
DOMAIN="${3:-backend}"
ENVIRONMENT="${4:-develop}"

echo "🚀 使用ServiceAccount认证的K8s部署"
echo "📋 部署配置:"
echo "  命名空间: $NAMESPACE"
echo "  应用名称: $APP_NAME"
echo "  域: $DOMAIN"
echo "  环境: $ENVIRONMENT"

# 检查是否在Kubernetes pod中运行
check_kubernetes_environment() {
    echo "🔍 检查运行环境..."

    # 检查是否在K8s pod中
    if [[ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]]; then
        echo "✅ 检测到Kubernetes pod环境"
        K8S_IN_POD=true
    else
        echo "ℹ️ 非Kubernetes pod环境，使用默认配置"
        K8S_IN_POD=false
    fi
}

# 配置ServiceAccount认证
setup_serviceaccount_auth() {
    echo "🔧 配置ServiceAccount认证..."

    if [[ "$K8S_IN_POD" == "true" ]]; then
        # 在pod中使用ServiceAccount token
        export KUBECONFIG="/tmp/kubeconfig-serviceaccount"

        # 获取pod的信息
        K8S_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
        K8S_CA=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
        K8S_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
        K8S_HOST=$(cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt | openssl x509 -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | cut -d: -f2 | tr -d ' ' || echo "kubernetes.default.svc")

        # 创建kubeconfig文件
        cat > "$KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: in-cluster
  cluster:
    certificate-authority-data: $(echo "$K8S_CA" | base64 -w 0)
    server: https://kubernetes.default.svc
contexts:
- name: in-cluster
  context:
    cluster: in-cluster
    namespace: $K8S_NAMESPACE
    user: in-cluster-user
current-context: in-cluster
users:
- name: in-cluster-user
  user:
    token: $K8S_TOKEN
EOF

        echo "✅ ServiceAccount认证配置完成"
        echo "  KUBECONFIG: $KUBECONFIG"
        echo "  Namespace: $K8S_NAMESPACE"
    else
        # 使用现有的kubeconfig配置方法
        setup_standard_config
    fi
}

# 标准kubeconfig配置（备用方案）
setup_standard_config() {
    echo "🔧 使用标准kubeconfig配置..."

    # 尝试多种方式设置KUBECONFIG
    CURRENT_USER=$(whoami)
    echo "🔍 当前用户: $CURRENT_USER"

    # 方法1: 直接设置已知路径
    if [[ -f "/home/zeng/.kube/config" ]]; then
        export KUBECONFIG="/home/zeng/.kube/config"
        echo "✅ 方法1成功: 设置KUBECONFIG=$KUBECONFIG"
    # 方法2: 当前用户home目录
    elif [[ -f "$HOME/.kube/config" ]]; then
        export KUBECONFIG="$HOME/.kube/config"
        echo "✅ 方法2成功: 设置KUBECONFIG=$KUBECONFIG"
    # 方法3: root用户目录
    elif [[ -f "/root/.kube/config" ]]; then
        export KUBECONFIG="/root/.kube/config"
        echo "✅ 方法3成功: 设置KUBECONFIG=$KUBECONFIG"
    # 方法4: 使用GitHub Actions Secrets
    elif [[ -n "$KUBE_CONFIG_DATA" ]]; then
        echo "🔧 使用GitHub Actions Secrets..."
        mkdir -p ~/.kube
        echo "$KUBE_CONFIG_DATA" | base64 -d > ~/.kube/config
        export KUBECONFIG="$HOME/.kube/config"
        echo "✅ 方法4成功: 使用Secrets设置KUBECONFIG=$KUBECONFIG"
    else
        echo "❌ 所有方法都失败了"
        echo "🔍 调试信息:"
        echo "  HOME: $HOME"
        echo "  当前用户: $(whoami)"
        echo "  KUBE_CONFIG_DATA: ${KUBE_CONFIG_DATA:+已设置}"
        exit 1
    fi
}

# 验证K8s连接
verify_k8s_connection() {
    echo "🔍 验证Kubernetes连接..."

    # 验证配置文件存在
    if [[ ! -f "$KUBECONFIG" ]]; then
        echo "❌ kubeconfig文件不存在: $KUBECONFIG"
        exit 1
    fi

    echo "✅ kubeconfig文件存在，大小: $(wc -c < "$KUBECONFIG") bytes"

    # 验证服务器地址和上下文
    SERVER_URL=$(grep "server:" "$KUBECONFIG" | awk '{print $2}')
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "未知")

    echo "🌐 服务器地址: $SERVER_URL"
    echo "🎯 当前上下文: $CURRENT_CONTEXT"

    # 测试连接
    if kubectl cluster-info --request-timeout=30s > /dev/null 2>&1; then
        echo "✅ Kubernetes连接验证通过"
    else
        echo "❌ 无法连接到Kubernetes集群"
        echo "🔍 集群诊断信息:"
        echo "  当前用户: $(whoami)"
        echo "  KUBECONFIG: ${KUBECONFIG:-'未设置'}"
        kubectl config get-contexts || echo "无法获取contexts"
        exit 1
    fi
}

# 检查ServiceAccount权限
check_serviceaccount_permissions() {
    echo "🔍 检查ServiceAccount权限..."

    # 检查当前用户权限
    if kubectl auth can-i create deployments; then
        echo "✅ 有创建deployments的权限"
    else
        echo "❌ 没有创建deployments的权限"
        echo "💡 可能需要更新RBAC配置"
    fi

    if kubectl auth can-i create services; then
        echo "✅ 有创建services的权限"
    else
        echo "❌ 没有创建services的权限"
    fi

    if kubectl auth can-i create namespaces; then
        echo "✅ 有创建namespaces的权限"
    else
        echo "⚠️ 没有创建namespaces的权限（可能需要预先创建）"
    fi
}

# 执行部署
perform_deployment() {
    echo "🚀 开始执行部署..."

    # 创建 namespace（如果不存在）
    echo "🏷️ 创建 namespace: $NAMESPACE"
    if kubectl auth can-i create namespaces; then
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    else
        echo "ℹ️ 使用现有namespace: $NAMESPACE"
    fi

    # 选择对应的 K8s 配置文件
    K8S_CONFIG="deploy/k8s/${DOMAIN}-${APP_NAME}.yaml"
    if [ ! -f "$K8S_CONFIG" ]; then
        echo "❌ K8s 配置文件不存在: $K8S_CONFIG"
        echo "📂 可用的K8s配置文件:"
        ls -la deploy/k8s/ || echo "deploy/k8s/ 目录不存在"
        exit 1
    fi

    echo "📝 使用配置文件: $K8S_CONFIG"

    # 准备环境变量替换
    REGISTRY="${REGISTRY:-localhost:5000}"
    IMAGE_TAG="${IMAGE_TAG:-latest}"
    FULL_IMAGE_NAME="${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"

    # 设置默认的敏感数据值（生产环境需要替换为实际值）
    DB_PASSWORD="$(echo -n 'default-password' | base64)"
    API_KEY="$(echo -n 'default-api-key' | base64)"
    SESSION_SECRET="$(echo -n 'default-session-secret' | base64)"

    # 根据环境设置 API 基础 URL
    case "$ENVIRONMENT" in
        "develop")
            API_BASE_URL="http://backend-${APP_NAME}-service.app-${NAMESPACE}.svc.cluster.local"
            ;;
        "staging")
            API_BASE_URL="https://staging-api.example.com"
            ;;
        "prod")
            API_BASE_URL="https://api.example.com"
            ;;
        *)
            API_BASE_URL="http://localhost:8080"
            ;;
    esac

    # 使用 envsubst 替换配置文件中的变量
    echo "🔄 替换配置文件变量..."
    envsubst < "$K8S_CONFIG" > "/tmp/${APP_NAME}-config.yaml"

    # 验证替换后的配置文件
    echo "📋 验证配置文件..."
    if ! kubectl apply --dry-run=client -f "/tmp/${APP_NAME}-config.yaml"; then
        echo "❌ 配置文件验证失败"
        exit 1
    fi

    # 部署应用
    echo "☸️ 部署应用到 $NAMESPACE namespace..."
    kubectl apply -f "/tmp/${APP_NAME}-config.yaml"

    # 等待部署完成
    echo "⏳ 等待部署完成..."
    DEPLOYMENT_NAME="${DOMAIN}-${APP_NAME}"
    echo "🎯 等待部署: $DEPLOYMENT_NAME"

    if kubectl rollout status deployment/"$DEPLOYMENT_NAME" --namespace="$NAMESPACE" --timeout=120s; then
        echo "✅ 部署成功完成"

        # 显示部署状态
        echo "📊 部署状态:"
        kubectl get pods -n "$NAMESPACE" -l "app=${DOMAIN}-${APP_NAME}" -l "environment=${ENVIRONMENT}"
        kubectl get services -n "$NAMESPACE" -l "app=${DOMAIN}-${APP_NAME}" -l "environment=${ENVIRONMENT}"
    else
        echo "❌ 部署失败"

        # 显示失败的 pod 状态
        echo "🔍 失败的 pod 状态:"
        kubectl get pods -n "$NAMESPACE" -l "app=${DOMAIN}-${APP_NAME}" -l "environment=${ENVIRONMENT}"
        kubectl describe pods -n "$NAMESPACE" -l "app=${DOMAIN}-${APP_NAME}" -l "environment=${ENVIRONMENT}" | tail -20
        exit 1
    fi

    # 清理临时文件
    rm -f "/tmp/${APP_NAME}-config.yaml"
}

# 主函数
main() {
    echo "🚀 开始ServiceAccount认证部署..."

    # 检查环境
    check_kubernetes_environment

    # 配置认证
    setup_serviceaccount_auth

    # 验证连接
    verify_k8s_connection

    # 检查权限
    check_serviceaccount_permissions

    # 执行部署
    perform_deployment

    echo "✅ ServiceAccount认证部署完成"
}

# 执行主函数
main "$@"