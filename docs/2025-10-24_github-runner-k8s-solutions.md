# GitHub Runner 与 K8s 集成解决方案总结

## 📋 问题概述

本文档总结了解决 GitHub Runner 在 Kubernetes 环境中的两个关键问题：
1. **GitHub Runner 启动失败**：token 过期导致无法向 GitHub 注册
2. **GitHub Actions K8s 连接失败**：Runner 在 pod 中运行时缺乏适当的 K8s 认证配置

## 🔍 根本原因分析

### 问题1: GitHub Runner 启动失败
- **根本原因**: GitHub Runner token 有效期仅为 1 小时
- **表现**: Runner pod 持续处于 `CrashLoopBackOff` 状态
- **错误信息**: `Http response code: NotFound from 'POST https://api.github.com/actions/runner-registration'`

### 问题2: GitHub Actions K8s 连接失败
- **根本原因**: GitHub Actions 运行在隔离环境中，无法直接访问本地 kubeconfig 文件
- **表现**: 部署阶段无法连接到 K8s 集群，显示 "KUBECONFIG: '未设置'"
- **环境限制**: GitHub Actions 在 pod 中运行时缺乏文件系统访问权限

## ✅ 已实施的解决方案

### 1. Kubernetes ServiceAccount 认证系统

#### 1.1 创建专用 ServiceAccount
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner-actions-sa
  namespace: github-runners
  labels:
    app: github-runner
    component: service-account
    purpose: actions-auth
```

#### 1.2 配置 ClusterRole 和权限
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-actions-role
rules:
  # 基础权限
  - apiGroups: [""]
    resources: ["namespaces", "pods", "services", "configmaps", "secrets", "events"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # 应用部署权限
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # 网络权限
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

#### 1.3 应用 RBAC 配置
```bash
kubectl apply -f deploy/k8s/github-runner-rbac.yaml
```

**结果**: ✅ 成功创建 ServiceAccount、ClusterRole 和相关绑定

### 2. GitHub Runner 自动 Token 更新机制

#### 2.1 创建 Token 更新脚本
创建了 `scripts/update-runner-token.sh` 脚本，具备以下功能：
- 自动检查 GitHub CLI 依赖
- 获取新的 runner registration token
- 更新 Kubernetes secret
- 自动重启 runner deployment
- 验证 runner 状态

#### 2.2 GitHub CLI 安装
```bash
# 添加 GitHub CLI GPG 密钥
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg

# 添加 APT 仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# 安装 GitHub CLI
sudo apt update && sudo apt install -y gh
```

**结果**: ✅ GitHub CLI 2.82.1 安装成功

### 3. ServiceAccount 认证部署脚本

创建了 `scripts/deploy-with-serviceaccount.sh` 脚本，具备以下功能：
- 自动检测 K8s pod 环境
- 配置 ServiceAccount 内部认证
- 验证 K8s 连接和权限
- 执行应用部署
- 权限检查和错误处理

## 🛠️ 实施步骤

### 步骤 1: 更新 GitHub Runner ServiceAccount
```bash
kubectl patch deployment github-runner-simple -n github-runners -p '{"spec":{"template":{"spec":{"serviceAccountName":"github-runner-actions-sa"}}}}'
```

### 步骤 2: 验证 ServiceAccount 权限
```bash
# 检查权限
kubectl auth can-i create deployments --as=system:serviceaccount:github-runners:github-runner-actions-sa

# 检查当前 Runner 状态
kubectl get pods -n github-runners -l app=github-runner
```

### 步骤 3: 更新 Runner Token（需要时）
```bash
# 生成并应用新 token
./scripts/generate-github-token.sh

# 或使用完整更新脚本
./scripts/update-runner-token.sh
```

## 📊 解决方案优势

### 1. ServiceAccount 认证方案
✅ **安全性高**：使用 K8s 内置认证机制
✅ **无需手动维护**：自动继承权限配置
✅ **权限精确控制**：细粒度的 RBAC 权限管理
✅ **环境兼容**：适用于任何 K8s 环境

### 2. 自动 Token 更新机制
✅ **自动化程度高**：无需人工干预
✅ **快速恢复**：自动检测并修复 token 问题
✅ **状态监控**：完整的验证和检查流程
✅ **错误处理**：详细的日志和故障排除信息

### 3. 统一部署脚本
✅ **环境自适应**：自动检测运行环境
✅ **容错性强**：多重认证方案支持
✅ **权限验证**：部署前权限检查
✅ **操作透明**：详细的执行日志

## 🔄 下一步操作

### 1. 验证 ServiceAccount 配置
```bash
# 检查 pod 是否使用新的 ServiceAccount
kubectl get pods -n github-runners -o yaml | grep serviceAccountName

# 验证权限是否正确
kubectl auth can-i create deployments --as=system:serviceaccount:github-runners:github-runner-actions-sa
```

### 2. 生成并应用新的 Runner Token
```bash
# 需要先登录 GitHub CLI
gh auth login

# 生成新 token 并更新 secret
./scripts/generate-github-token.sh
```

### 3. 测试自动部署流程
```bash
# 推送测试代码到目标分支
git push origin develop-backend-first-app

# 观察 GitHub Actions 执行情况
# 应该能够成功连接 K8s 并完成部署
```

### 4. 验证完整 CI/CD 流程
- ✅ 代码构建
- ✅ 镜像推送
- ✅ K8s 连接
- ✅ 应用部署
- ✅ 健康检查

## 📝 相关文件

### 脚本文件
- `scripts/update-runner-token.sh` - GitHub Runner token 自动更新脚本
- `scripts/generate-github-token.sh` - GitHub token 生成工具
- `scripts/deploy-with-serviceaccount.sh` - ServiceAccount 认证部署脚本

### 配置文件
- `deploy/k8s/github-runner-rbac.yaml` - ServiceAccount 和 RBAC 配置

### 文档
- `docs/2025-10-24_github-runner-k8s-solutions.md` - 本解决方案总结文档

## 🎯 预期效果

实施此解决方案后，预期实现：

1. **GitHub Runner 自动恢复能力**：token 过期后能自动更新并重启
2. **K8s 连接权限问题解决**：GitHub Actions 能在 pod 环境中正常连接和操作 K8s
3. **CI/CD 流程完全自动化**：从代码提交到应用部署的全流程自动化
4. **系统稳定性提升**：减少因认证问题导致的部署失败
5. **运维效率提高**：减少手动干预和故障排除时间

## 🔧 故障排除

### 如果 Runner 仍然无法启动
1. 检查 ServiceAccount 是否正确配置
2. 验证 GitHub CLI 认证状态
3. 查看 Runner pod 日志：`kubectl logs -f deployment/github-runner-simple -n github-runners`

### 如果 K8s 连接仍然失败
1. 验证 ServiceAccount 权限：`kubectl auth can-i --as=system:serviceaccount:github-runners:github-runner-actions-sa`
2. 检查 kubeconfig 配置
3. 验证集群连接状态

### 如果权限不足
1. 检查 ClusterRole 配置
2. 验证 ClusterRoleBinding
3. 根据需要调整权限范围

---

**解决方案状态**: ✅ 已实施
**最后更新**: 2025-10-24
**适用版本**: Kubernetes 1.30+, GitHub Actions 自托管 Runner