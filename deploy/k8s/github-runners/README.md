# GitHub Runner K8s 部署

## 📋 概述

本项目在本地 Kubernetes 集群中部署了 GitHub Actions Runner，用于在 K8s 环境中执行 GitHub Actions 工作流。

## 🏗️ 架构

- **Namespace**: `github-runners`
- **Runner 名称**: `k8s-runner-local`
- **目标仓库**: `gszw90/k8s-app`
- **Runner 类型**: Self-hosted, Linux
- **权限模式**: Root (required for Docker access)

## 📁 文件结构

```
k8s/github-runners/
├── namespace.yaml        # 命名空间配置
├── configmap.yaml        # 配置映射
├── secret.yaml           # 敏感信息存储
├── deployment.yaml       # 部署配置
├── rbac.yaml            # 权限配置
└── README.md            # 本文档
```

## 🚀 快速部署

### 1. 使用管理脚本（推荐）

```bash
# 部署 Runner
./scripts/github-runner-manager.sh deploy

# 查看状态
./scripts/github-runner-manager.sh status

# 查看日志
./scripts/github-runner-manager.sh logs

# 重启 Runner
./scripts/github-runner-manager.sh restart

# 扩展 Runner 数量
./scripts/github-runner-manager.sh scale 3

# 清理资源
./scripts/github-runner-manager.sh cleanup
```

### 2. 手动部署

```bash
# 创建命名空间
kubectl apply -f k8s/github-runners/namespace.yaml

# 创建配置
kubectl apply -f k8s/github-runners/configmap.yaml
kubectl apply -f k8s/github-runners/secret.yaml

# 创建权限
kubectl apply -f k8s/github-runners/rbac.yaml

# 部署 Runner
kubectl apply -f k8s/github-runners/deployment.yaml
```

## 📊 状态检查

### 查看 Runner 状态

```bash
# 查看所有资源
kubectl get all -n github-runners

# 查看 Pod 状态
kubectl get pods -n github-runners -o wide

# 查看 Deployment 状态
kubectl get deployments -n github-runners

# 查看事件
kubectl get events -n github-runners --sort-by=.metadata.creationTimestamp
```

### 查看日志

```bash
# 查看当前 Runner 日志
kubectl logs -n github-runners -l app=github-runner -f

# 查看特定 Pod 日志
kubectl logs -n github-runners <pod-name> -f
```

## ⚙️ 配置说明

### 环境变量

| 变量名 | 值 | 说明 |
|--------|-----|------|
| `RUNNER_NAME` | `k8s-runner-local` | Runner 名称 |
| `REPO_URL` | `https://github.com/gszw90/k8s-app` | GitHub 仓库 URL |
| `RUNNER_REPO` | `gszw90/k8s-app` | GitHub 仓库名 |
| `RUNNER_TOKEN` | `AGZXWBL5U6244YQD4OIS4SDI6DIAG` | Runner Token |
| `RUNNER_LABELS` | `k8s,self-hosted,local` | Runner 标签 |
| `RUNNER_GROUP` | `default` | Runner 组 |

### 资源配置

- **CPU**: 500m - 2000m
- **内存**: 1Gi - 4Gi
- **工作目录**: 10Gi 临时存储

### 权限配置

- **ServiceAccount**: `github-runner-sa`
- **Role**: Pod、ConfigMap、Secret 管理权限
- **ClusterRole**: Namespace、Node 查看权限

## 🔧 维护操作

### 重启 Runner

```bash
# 重启 Deployment
kubectl rollout restart deployment/github-runner -n github-runners

# 使用管理脚本
./scripts/github-runner-manager.sh restart
```

### 扩展 Runner

```bash
# 扩展到 3 个副本
kubectl scale deployment/github-runner -n github-runners --replicas=3

# 使用管理脚本
./scripts/github-runner-manager.sh scale 3
```

### 更新配置

```bash
# 更新 ConfigMap
kubectl apply -f k8s/github-runners/configmap.yaml

# 更新 Deployment
kubectl apply -f k8s/github-runners/deployment.yaml

# 重启以应用新配置
kubectl rollout restart deployment/github-runner -n github-runners
```

### 更新 Token

```bash
# 更新 Secret
kubectl edit secret github-runner-secret -n github-runners

# 重启 Runner
kubectl rollout restart deployment/github-runner -n github-runners
```

## 🔍 故障排除

### 常见问题

1. **Pod 无法启动**
   ```bash
   kubectl describe pod <pod-name> -n github-runners
   kubectl logs <pod-name> -n github-runners
   ```

2. **Runner 无法连接 GitHub**
   - 检查 Token 是否正确
   - 检查网络连接
   - 查看日志中的错误信息

3. **权限问题**
   ```bash
   kubectl auth can-i create pods -n github-runners --as=system:serviceaccount:github-runners:github-runner-sa
   ```

4. **Docker 权限问题**
   - 确保 Docker Socket 正确挂载
   - 检查节点上的 Docker 权限

### 调试命令

```bash
# 进入 Pod 调试
kubectl exec -it <pod-name> -n github-runners -- /bin/bash

# 查看配置
kubectl get configmap github-runner-config -n github-runners -o yaml

# 查看密钥
kubectl get secret github-runner-secret -n github-runners -o yaml

# 查看权限
kubectl describe role github-runner-role -n github-runners
```

## 📈 监控

### Runner 状态监控

- **Pod 状态**: 使用 `kubectl get pods`
- **资源使用**: `kubectl top pods -n github-runners`
- **日志监控**: `kubectl logs -f`
- **事件监控**: `kubectl get events`

### GitHub 状态

- 在 GitHub 仓库的 Settings > Actions 中查看 Runner 状态
- 查看 Runner 的活动和作业历史

## 🔒 安全注意事项

1. **Token 管理**: 定期更新 Runner Token
2. **权限最小化**: 只授予必要的 K8s 权限
3. **网络隔离**: 考虑使用 NetworkPolicy
4. **资源限制**: 设置适当的资源限制
5. **日志监控**: 定期检查 Runner 日志

## 📚 相关资源

- [GitHub Actions 官方文档](https://docs.github.com/en/actions)
- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Docker 官方文档](https://docs.docker.com/)

## 🆘 获取帮助

```bash
# 查看管理脚本帮助
./scripts/github-runner-manager.sh help

# 查看更多 kubectl 命令
kubectl --help
```