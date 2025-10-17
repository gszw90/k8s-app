# GitHub Token 重新生成指南

## 🎯 问题分析
当前Runner的RUNNER_TOKEN已失效（404错误），需要重新生成。

## 📋 步骤1：在GitHub上重新生成Token

### 方法A：通过GitHub UI（推荐）
1. 访问您的仓库：https://github.com/gszw90/k8s-app
2. 点击 **Settings** 标签页
3. 在左侧菜单中找到 **Actions** → **Runners**
4. 点击 **New self-hosted runner** 按钮
5. 选择 **Linux** 和 **x64** 架构
6. 在下载部分下方，找到 **Configure** 部分
7. 复制 **Token**（格式类似：`A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0`）

### 方法B：通过GitHub CLI
```bash
# 安装GitHub CLI（如果尚未安装）
# Windows: winget install GitHub.cli
# macOS: brew install gh
# Linux: sudo apt install gh

# 登录GitHub
gh auth login

# 创建Runner Token（需要repo权限）
gh api --method POST -H "Accept: application/vnd.github.v3+json" /repos/gszw90/k8s-app/actions/runners/registration-token
```

## 📋 步骤2：更新K8s Secret

获取新Token后，执行以下命令更新Secret：

```bash
# 设置新Token（替换 YOUR_NEW_TOKEN_HERE）
NEW_TOKEN="YOUR_NEW_TOKEN_HERE"

# 更新Secret
kubectl patch secret github-runner-secret \
  --namespace github-runners \
  --patch='{"data":{"RUNNER_TOKEN":"'$(echo -n $NEW_TOKEN | base64)'"}}'

# 验证更新
kubectl get secret github-runner-secret \
  --namespace github-runners \
  -o jsonpath='{.data.RUNNER_TOKEN}' | base64 -d
```

## 📋 步骤3：部署新的持久化Runner

```bash
# 1. 创建持久化存储
kubectl apply -f github-runner-fixed.yaml --namespace github-runners

# 2. 等待Pod启动
kubectl get pods --namespace github-runners -w

# 3. 查看Pod日志
kubectl logs -f deployment/github-runner-fixed --namespace github-runners
```

## 📋 步骤4：验证Runner状态

1. **检查Pod状态**：
```bash
kubectl get pods --namespace github-runners
```

2. **查看Runner注册状态**：
```bash
kubectl logs deployment/github-runner-fixed --namespace github-runners --tail=20
```

3. **在GitHub中验证**：
   - 访问 https://github.com/gszw90/k8s-app/settings/actions/runners
   - 查看Runner是否显示为 **Idle** 状态

## 📋 步骤5：测试工作流程

推送代码到 `develop-backend-first-app` 分支触发工作流程：

```bash
# 推送测试代码（如果需要）
git checkout develop-backend-first-app
git commit --allow-empty -m "测试Runner修复"
git push origin develop-backend-first-app
```

## 🎯 预期结果

- ✅ Runner Pod状态为 `Running`
- ✅ GitHub中Runner显示为 `Idle`
- ✅ 工作流程正常执行，不再阻塞

## 🔧 故障排除

### 如果仍然失败：
1. **检查日志**：`kubectl logs -f deployment/github-runner-fixed --namespace github-runners`
2. **验证Token**：确保Token格式正确且未过期
3. **检查权限**：确认仓库权限设置正确
4. **查看事件**：`kubectl get events --namespace github-runners --sort-by=.metadata.creationTimestamp`

### 常见错误：
- `404 Not Found`：Token无效或过期
- `403 Forbidden`：权限不足
- `Connection refused`：网络问题

## 🎓 学习价值

通过这个过程，您学会了：
1. **Token生命周期管理**：理解和重新生成认证Token
2. **K8s Secret管理**：安全地更新配置
3. **持久化存储配置**：PVC和状态管理
4. **故障排查流程**：系统化的问题解决方法