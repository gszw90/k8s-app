#!/bin/bash

# GitHub Runner Pod内kubectl安装和配置脚本
# 基于in-cluster Kubernetes通信方案

set -e

echo "🔧 开始安装和配置kubectl..."

# 更新包管理器并安装必要工具
echo "📦 安装系统依赖..."
apt-get update
apt-get install -y curl gnupg2 ca-certificates apt-transport-https

# 下载并安装kubectl
echo "⬇️ 下载kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

# 安装kubectl
echo "🛠️ 安装kubectl..."
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 验证安装
echo "✅ 验证kubectl安装..."
kubectl version --client

# 创建kubeconfig目录
echo "📁 创建kubeconfig目录..."
mkdir -p ~/.kube

# 生成in-cluster kubeconfig配置
echo "⚙️ 生成in-cluster kubeconfig..."
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

# 设置环境变量
export KUBECONFIG="$HOME/.kube/config"

# 测试kubectl连接
echo "🔍 测试kubectl连接..."
kubectl cluster-info
kubectl get namespaces
kubectl auth can-i create deployments --all-namespaces

echo "✅ kubectl安装和配置完成！"
echo ""
echo "📋 可用命令:"
echo "  kubectl get pods -n <namespace>"
echo "  kubectl apply -f <yaml-file>"
echo "  kubectl get deployments -n <namespace>"
echo ""
echo "🎯 当前上下文: $(kubectl config current-context)"
echo "🔐 当前用户: $(kubectl config view -o jsonpath='{.users[0].name}')"