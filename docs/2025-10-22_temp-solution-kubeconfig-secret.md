# GitHub Actions K8s连接 - 临时解决方案

## 🚨 临时解决方案：使用GitHub Actions Secrets

### 方案概述

由于GitHub Actions无法直接访问本地文件系统中的kubeconfig，我们使用GitHub Actions Secrets来存储kubeconfig内容。

### 🛠️ 实施步骤

#### 步骤1: 准备kubeconfig内容

```bash
# 1. 将kubeconfig编码为base64
cat /home/zeng/.kube/config | base64 -w 0

# 2. 复制输出的base64字符串
# 输出示例:
# YXBpVmVyc2lvbjogdjEKY2x1c3RlcnM6Ci0gY2x1c3RlcjoKICAgIGNlcnRpZmljYXRlLWF1dGhvcml0eS1kYXRhOiBMUz...
```

#### 步骤2: 在GitHub仓库中设置Secret

1. 进入GitHub仓库页面
2. Settings → Secrets and variables → Actions
3. 点击 "New repository secret"
4. Name: `KUBE_CONFIG_DATA`
5. Secret: 粘贴步骤1中获得的base64字符串
6. 点击 "Add secret"

#### 步骤3: 修改GitHub Actions工作流

在 `.github/workflows/deploy-monorepo.yaml` 中，部署步骤应该已经包含了对 `KUBE_CONFIG_DATA` 的支持：

```yaml
# 使用现有的KUBECONFIG环境变量配置
if [[ -n "$KUBE_CONFIG_DATA" ]]; then
    echo "🔧 使用外部KUBECONFIG..."
    mkdir -p ~/.kube
    echo "$KUBE_CONFIG_DATA" | base64 -d > ~/.kube/config
    export KUBECONFIG="$HOME/.kube/config"
    echo "✅ 外部KUBECONFIG设置完成: $KUBECONFIG"
```

### 🔍 验证方案

#### 测试1: 本地验证
```bash
# 模拟GitHub Actions环境
KUBE_CONFIG_DATA=$(cat /home/zeng/.kube/config | base64 -w 0)
mkdir -p ~/.kube/test
echo "$KUBE_CONFIG_DATA" | base64 -d > ~/.kube/test/config
export KUBECONFIG="$HOME/.kube/test/config"
kubectl cluster-info
```

#### 测试2: GitHub Actions验证
推送代码到相关分支，观察GitHub Actions日志：
- 应该显示 "🔧 使用外部KUBECONFIG..."
- 应该成功创建kubeconfig文件
- 应该成功连接到K8s集群

### 📋 临时方案优缺点

#### ✅ 优点
1. **可靠性**: 不依赖本地文件系统访问
2. **安全性**: 使用GitHub Secrets加密存储
3. **兼容性**: 适用于任何GitHub Actions环境
4. **简单性**: 实施简单，只需设置一个Secret

#### ⚠️ 缺点
1. **维护性**: 如果kubeconfig发生变化，需要更新Secret
2. **安全性**: 敏感信息存储在GitHub（虽然有加密）
3. **临时性**: 这是一个临时解决方案，需要后续寻找更好的方案

### 🔄 后续改进方向

1. **动态配置**: 实现动态获取kubeconfig的方法
2. **服务账户**: 使用K8s服务账户进行认证
3. **环境隔离**: 为不同环境配置不同的认证方式

### 🚀 立即行动项

1. **执行kubeconfig编码**: `cat /home/zeng/.kube/config | base64 -w 0`
2. **在GitHub中设置Secret**: 创建 `KUBE_CONFIG_DATA`
3. **测试部署**: 推送代码验证方案是否有效
4. **监控结果**: 观察GitHub Actions执行结果

---

**这个临时方案应该能够立即解决当前的部署问题，为后续寻找更好的解决方案争取时间。**