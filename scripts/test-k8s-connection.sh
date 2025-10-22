#!/bin/bash

# GitHub Actions K8s连接测试脚本
# 模拟GitHub Actions部署步骤中的K8s连接验证

echo "🧪 测试GitHub Actions K8s连接配置"
echo "======================================"

# 模拟GitHub Actions环境
echo "🔧 模拟GitHub Actions环境..."

# 加载系统环境变量（包括KUBECONFIG）
echo "🔧 加载系统环境变量..."
if [[ -f "/etc/profile" ]]; then
    source /etc/profile
    echo "✅ 已加载 /etc/profile"
else
    echo "❌ /etc/profile 不存在"
    exit 1
fi

# 验证KUBECONFIG是否已设置
echo "🔍 验证环境变量..."
echo "KUBECONFIG: ${KUBECONFIG:-'未设置'}"

if [[ -z "$KUBECONFIG" ]]; then
    echo "❌ KUBECONFIG 环境变量未设置"
    exit 1
fi

# 使用现有的KUBECONFIG环境变量配置
echo "🔧 使用现有KUBECONFIG环境变量: $KUBECONFIG"

# 验证配置文件是否存在且可访问
if [[ -f "$KUBECONFIG" ]]; then
    echo "✅ kubeconfig文件存在，大小: $(wc -c < "$KUBECONFIG") bytes"

    # 验证服务器地址和上下文
    SERVER_URL=$(grep "server:" "$KUBECONFIG" | awk '{print $2}')
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "未知")

    echo "🌐 服务器地址: $SERVER_URL"
    echo "🎯 当前上下文: $CURRENT_CONTEXT"
    echo "✅ KUBECONFIG环境变量配置完成"
else
    echo "❌ KUBECONFIG指向的文件不存在: $KUBECONFIG"
    exit 1
fi

# 检查并安装kubectl
if ! command -v kubectl &> /dev/null; then
    echo "📦 kubectl 未安装，正在安装..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "✅ kubectl 安装完成"
else
    echo "✅ kubectl 已安装: $(kubectl version --client --short 2>/dev/null || echo '版本未知')"
fi

# 验证 K8s 集群连接
echo "🔍 验证集群连接..."
if kubectl cluster-info --request-timeout=30s; then
    echo "✅ 集群连接验证通过"

    # 额外验证
    echo "📊 额外验证信息:"
    echo "  当前用户: $(whoami)"
    echo "  命名空间列表:"
    kubectl get namespaces | head -5
    echo "  节点状态:"
    kubectl get nodes

    echo ""
    echo "🎉 所有测试通过！GitHub Actions应该能够成功连接到K8s集群"

else
    echo "❌ 无法连接到 Kubernetes 集群"
    echo "🔍 集群诊断信息:"
    echo "  当前用户: $(whoami)"
    echo "  KUBECONFIG: ${KUBECONFIG:-'未设置'}"
    echo "  尝试列出集群:"
    kubectl config get-contexts || echo "无法获取contexts"
    exit 1
fi

echo ""
echo "🔧 故障排除建议:"
echo "1. 确保 Docker Desktop Kubernetes 正在运行"
echo "2. 检查 /etc/profile 中的 KUBECONFIG 设置"
echo "3. 验证 kubeconfig 文件权限: ls -la $KUBECONFIG"
echo "4. 手动测试: kubectl cluster-info"