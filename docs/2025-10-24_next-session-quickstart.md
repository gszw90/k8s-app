# 下一会话快速开始指南

## 🎯 会话恢复检查清单

当您下次继续时，请按以下顺序检查和执行：

### 1. 环境状态验证 (5分钟)
```bash
# 检查当前分支
git branch

# 检查GitHub CLI状态
gh auth status

# 检查Kubernetes集群
kubectl cluster-info

# 检查基础设施状态
kubectl get namespace actions-runner-system
kubectl get secret controller-manager -n actions-runner-system
```

### 2. 网络连接测试 (2分钟)
```bash
# 测试GitHub API连接
curl -I https://api.github.com

# 测试GitHub releases连接
curl -I https://github.com/actions/actions-runner-controller/releases

# 如果都正常，可以继续ARC部署
# 如果超时，使用混合架构方案
```

### 3. 核心功能测试 (10分钟)
```bash
# 测试GitHub App token更新脚本
./scripts/update-runner-token-github-app.sh --help

# 如果脚本运行正常，执行实际更新
./scripts/update-runner-token-github-app.sh

# 验证token更新效果
kubectl get secret github-runner-secret -n github-runners -o yaml
```

## 📋 决策树

### 网络正常情况 → 完整ARC部署
```bash
# 继续ARC Controller部署
kubectl apply -f https://github.com/actions/actions-runner-controller/releases/download/v0.23.7/actions-runner-controller.yaml

# 等待部署完成
kubectl wait --for=condition=available deployment/controller-manager -n actions-runner-system --timeout=300s

# 创建Runner资源
./scripts/create-arc-runners.sh develop staging prod
```

### 网络异常情况 → 混合架构实施
```bash
# 跳过ARC部署，直接使用混合方案

# 1. 创建智能扩展脚本
# (文件已准备，需要测试)

# 2. 部署CronJob定时任务
kubectl apply -f deploy/k8s/runner-token-updater-cronjob.yaml

# 3. 测试自动化流程
./scripts/update-runner-token-github-app.sh
```

## 🔧 关键文件快速访问

### 立即需要测试的文件
- `scripts/update-runner-token-github-app.sh` - ⭐ **最重要**
- `github-app-private-key.pem` - GitHub App认证
- `docs/2025-10-24_hybrid-solution-design.md` - 混合方案设计

### 需要创建的文件 (如果选择混合方案)
- `scripts/smart-runner-scaler.sh` - 智能扩展脚本
- `deploy/k8s/runner-token-updater-cronjob.yaml` - 定时任务
- `scripts/monitor-runner-health.sh` - 健康监控

## 🎯 预期结果

### 成功标准
1. ✅ GitHub App token自动更新成功
2. ✅ Runner pod正常运行无CrashLoopBackOff
3. ✅ CI/CD workflow可以正常执行
4. ✅ 自动化程度达到90%+

### 验证方法
```bash
# 检查runner状态
kubectl get pods -n github-runners

# 检查workflow执行
# (推送测试代码到develop-backend-first-app分支)

# 验证自动更新
# (等待2小时后检查token是否自动更新)
```

## 🚨 故障排查快速指南

### 如果GitHub App认证失败
```bash
# 检查私钥文件权限
ls -la github-app-private-key.pem

# 重新生成JWT测试
openssl dgst -sha256 -sign github-app-private-key.pem -out test.sig <(echo "test")
```

### 如果runner仍然无法启动
```bash
# 检查pod日志
kubectl logs -f deployment/github-runner-simple -n github-runners

# 检查secret内容
kubectl get secret github-runner-secret -n github-runners -o yaml

# 手动重启
kubectl rollout restart deployment/github-runner-simple -n github-runners
```

### 如果网络仍然超时
```bash
# 使用混合架构，无需完整ARC
# 已有的脚本可以独立解决问题

# 实施简化的自动更新方案
# 详见: docs/2025-10-24_hybrid-solution-design.md
```

## 📞 获取帮助

### 查看详细文档
- 完整架构设计: `docs/2025-10-24_arc-architecture-design.md`
- 混合方案设计: `docs/2025-10-24_hybrid-solution-design.md`
- 项目状态总结: `docs/2025-10-24_project-status-summary.md`

### 调试命令快速参考
```bash
# 查看所有相关资源
kubectl get all -n actions-runner-system
kubectl get all -n github-runners

# 查看事件
kubectl get events -n actions-runner-system --sort-by='.lastTimestamp'
kubectl get events -n github-runners --sort-by='.lastTimestamp'

# 查看日志
kubectl logs -f deployment/controller-manager -n actions-runner-system
kubectl logs -f deployment/github-runner-simple -n github-runners
```

---

**重要提醒**:
- 无论选择哪种方案，GitHub App token更新脚本都是核心，请优先测试
- 混合架构方案已经可以独立解决token过期问题
- ARC部署是增强功能，不是必需的前置条件

**预计时间**: 网络正常情况下30分钟内可完成核心功能验证