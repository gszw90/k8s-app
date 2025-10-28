#!/bin/bash

# GitHub Runner Pod内in-cluster配置脚本
# 用于设置Kubernetes in-cluster认证和配置

set -e

echo "🔧 配置GitHub Runner Pod内Kubernetes in-cluster连接..."

# 验证ServiceAccount Token存在
if [[ ! -f "/run/secrets/kubernetes.io/serviceaccount/token" ]]; then
    echo "❌ 错误: ServiceAccount Token文件不存在"
    exit 1
fi

# 验证CA证书存在
if [[ ! -f "/run/secrets/kubernetes.io/serviceaccount/ca.crt" ]]; then
    echo "❌ 错误: CA证书文件不存在"
    exit 1
fi

# 创建kubeconfig目录
echo "📁 创建kubeconfig目录..."
mkdir -p ~/.kube

# 生成in-cluster kubeconfig
echo "⚙️ 生成in-cluster kubeconfig配置..."
cat > ~/.kube/config << 'EOF'
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /run/secrets/kubernetes.io/serviceaccount/ca.crt
    server: https://kubernetes.default.svc
  name: in-cluster
contexts:
- context:
    cluster: in-cluster
    user: in-cluster-user
  name: in-cluster
current-context: in-cluster
kind: Config
preferences: {}
users:
- name: in-cluster-user
  user:
    tokenFile: /run/secrets/kubernetes.io/serviceaccount/token
EOF

# 设置权限
chmod 600 ~/.kube/config

# 设置环境变量
export KUBECONFIG="$HOME/.kube/config"
echo "export KUBECONFIG=\"$HOME/.kube/config\"" >> ~/.bashrc

# 测试连接
echo "🔍 测试Kubernetes API连接..."

# 测试基本API访问
echo "  - 测试API服务器连接..."
API_SERVER="https://kubernetes.default.svc"
TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)

if curl -k -s -H "Authorization: Bearer $TOKEN" "$API_SERVER/api/v1/namespaces" > /dev/null; then
    echo "  ✅ API服务器连接成功"
else
    echo "  ❌ API服务器连接失败"
    exit 1
fi

# 测试kubectl命令（如果已安装）
if command -v kubectl &> /dev/null; then
    echo "  - 测试kubectl命令..."

    # 测试集群信息
    if kubectl cluster-info &> /dev/null; then
        echo "  ✅ kubectl cluster-info 成功"
    else
        echo "  ⚠️  kubectl cluster-info 失败（可能权限不足）"
    fi

    # 测试命名空间访问
    if kubectl get namespaces &> /dev/null; then
        echo "  ✅ kubectl get namespaces 成功"
    else
        echo "  ⚠️  kubectl get namespaces 失败（可能权限不足）"
    fi

    # 显示当前上下文
    echo "  📋 当前上下文: $(kubectl config current-context)"
    echo "  👤 当前用户: $(kubectl config view -o jsonpath='{.users[0].name}')"
else
    echo "  ⚠️  kubectl未安装，请先运行 setup-kubectl-in-pod.sh"
fi

# 创建便捷脚本
echo "📝 创建便捷使用脚本..."
cat > ~/test-k8s-connection.sh << 'EOF'
#!/bin/bash
echo "🔍 测试Kubernetes连接状态..."

# 检查配置文件
if [[ -f "$HOME/.kube/config" ]]; then
    echo "  ✅ kubeconfig文件存在"
else
    echo "  ❌ kubeconfig文件不存在"
    exit 1
fi

# 检查Token
if [[ -f "/run/secrets/kubernetes.io/serviceaccount/token" ]]; then
    echo "  ✅ ServiceAccount Token存在"
else
    echo "  ❌ ServiceAccount Token不存在"
    exit 1
fi

# 测试API连接
TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)
API_SERVER="https://kubernetes.default.svc"

echo "  🌐 测试API服务器连接..."
if curl -k -s -H "Authorization: Bearer $TOKEN" "$API_SERVER/api/v1/namespaces" | jq -r '.items[].metadata.name' | head -5; then
    echo "  ✅ API连接正常"
else
    echo "  ❌ API连接失败"
    exit 1
fi

# 如果kubectl可用，测试kubectl命令
if command -v kubectl &> /dev/null; then
    echo "  🔧 测试kubectl命令..."
    kubectl get namespaces | head -5
    echo "  ✅ kubectl命令正常"
fi

echo "🎉 所有连接测试通过！"
EOF

chmod +x ~/test-k8s-connection.sh

# 创建GitHub Actions适配脚本
echo "🔄 创建GitHub Actions适配脚本..."
cat > ~/github-actions-k8s-setup.sh << 'EOF'
#!/bin/bash
# GitHub Actions Kubernetes配置脚本
# 在CI/CD中设置in-cluster Kubernetes连接

echo "🚀 设置GitHub Actions Kubernetes连接..."

# 设置kubeconfig
mkdir -p ~/.kube
cat > ~/.kube/config << 'EOF'
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /run/secrets/kubernetes.io/serviceaccount/ca.crt
    server: https://kubernetes.default.svc
  name: in-cluster
contexts:
- context:
    cluster: in-cluster
    user: in-cluster-user
  name: in-cluster
current-context: in-cluster
kind: Config
preferences: {}
users:
- name: in-cluster-user
  user:
    tokenFile: /run/secrets/kubernetes.io/serviceaccount/token
EOF

export KUBECONFIG="$HOME/.kube/config"

# 验证连接
echo "🔍 验证Kubernetes连接..."
if kubectl cluster-info &> /dev/null; then
    echo "✅ Kubernetes连接配置成功"
else
    echo "❌ Kubernetes连接配置失败"
    exit 1
fi

echo "🎯 准备就绪，可以开始Kubernetes部署操作！"
EOF

chmod +x ~/github-actions-k8s-setup.sh

echo ""
echo "✅ in-cluster Kubernetes配置完成！"
echo ""
echo "📋 可用脚本:"
echo "  ~/test-k8s-connection.sh    - 测试连接状态"
echo "  ~/github-actions-k8s-setup.sh - GitHub Actions环境设置"
echo ""
echo "🔧 环境变量已设置: KUBECONFIG=$HOME/.kube/config"
echo "🚀 可以开始使用kubectl进行Kubernetes操作！"