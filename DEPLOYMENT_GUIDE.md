# 🚀 K8s Monorepo 部署指南

## 📋 概述

本项目实现了基于分支名称的自动化 K8s 部署系统，支持多应用、多环境的 monorepo 架构。

## 🏗️ 架构设计

### 分支命名规范
- **格式**: `{environment}-{domain}-{app-name}`
- **示例**:
  - `develop-backend-first-app` → 开发环境的 backend first-app
  - `staging-frontend-web-app` → 预发布环境的 frontend web-app
  - `prod-backend-second-app` → 生产环境的 backend second-app

### 环境隔离策略
- **Namespace 隔离**: 每个环境使用独立的 namespace
  - `develop` → `app-develop`
  - `staging` → `app-staging`
  - `prod` → `app-prod`

### 目录结构
```
├── .github/workflows/
│   └── deploy-monorepo.yaml          # 统一的 CI/CD workflow
├── scripts/
│   ├── parse-branch.sh               # 分支解析脚本
│   ├── rollback.sh                   # 回滚脚本
│   └── deploy-status.sh              # 部署状态查看脚本
├── k8s/
│   ├── backend-first-app.yaml        # backend first-app 配置
│   ├── backend-second-app.yaml       # backend second-app 配置
│   └── frontend-first-app.yaml       # frontend first-app 配置
└── ...其他项目文件
```

## 🔧 核心功能

### 1. 自动化部署流程
1. **推送代码** 到对应分支（如 `develop-backend-first-app`）
2. **GitHub Actions** 自动触发
3. **解析分支信息** 提取环境、域、应用名
4. **构建 Docker 镜像**（仅 backend 应用）
5. **部署到 K8s** 使用对应 namespace 和配置
6. **健康检查** 验证部署状态

### 2. 镜像标签策略
- **主标签**: `{app-name}-{environment}:{commit-hash}`
- **最新标签**: `{app-name}-{environment}:latest`

### 3. 配置管理
- **ConfigMap**: 管理环境特定配置（日志级别、副本数等）
- **Secret**: 管理敏感数据（数据库密码、API密钥等）
- **环境变量**: 通过 `envsubst` 动态替换配置文件变量

### 4. 版本管理与回滚
- **保留历史**: 每个应用每个环境保留最近 10 个版本
- **手动回滚**: 使用 `rollback.sh` 脚本进行版本回滚
- **部署历史**: 通过 `kubectl rollout history` 查看

## 📝 使用方法

### 创建新分支部署
```bash
# 开发环境部署 backend first-app
git checkout -b develop-backend-first-app
git push origin develop-backend-first-app

# 预发布环境部署 frontend first-app
git checkout -b staging-frontend-first-app
git push origin staging-frontend-first-app

# 生产环境部署 backend second-app
git checkout -b prod-backend-second-app
git push origin prod-backend-second-app
```

### 查看部署状态
```bash
# 查看所有环境状态
./scripts/deploy-status.sh

# 查看特定环境状态
./scripts/deploy-status.sh develop
./scripts/deploy-status.sh staging
./scripts/deploy-status.sh prod
```

### 回滚操作
```bash
# 回滚到上一个版本
./scripts/rollback.sh backend-first-app develop

# 回滚到指定版本
./scripts/rollback.sh backend-first-app develop 3
```

### 本地访问服务
```bash
# 端口转发到本地
kubectl port-forward -n app-develop service/backend-first-app-service 8080:80

# 访问服务
curl http://localhost:8080/ping
```

## ⚙️ 环境配置

### 环境变量映射
| 环境 | 日志级别 | 副本数 | 命名空间 |
|------|----------|--------|----------|
| develop | DEBUG | 1 | app-develop |
| staging | INFO | 2 | app-staging |
| prod | WARN | 3 | app-prod |

### 应用端口映射
| 应用 | 端口 |
|------|------|
| backend-first-app | 18080 |
| backend-second-app | 18081 |
| frontend-first-app | 3000 |

## 🔍 故障排除

### 常见问题

1. **分支名称格式错误**
   ```
   ❌ 无效的分支名称格式: xxx
   正确格式: {environment}-{domain}-{app-name}
   示例: develop-backend-first-app
   ```

2. **K8s 集群连接失败**
   ```bash
   # 检查集群连接
   kubectl cluster-info

   # 检查当前上下文
   kubectl config current-context
   ```

3. **镜像构建失败**
   ```bash
   # 检查 Dockerfile 是否存在
   ls -la backend/deploy/Dockerfile-first-app

   # 检查 Docker 是否正常运行
   docker ps
   ```

4. **部署失败**
   ```bash
   # 查看 pod 状态
   kubectl get pods -n app-develop

   # 查看 pod 详细信息
   kubectl describe pod <pod-name> -n app-develop

   # 查看日志
   kubectl logs <pod-name> -n app-develop --tail=50
   ```

### 调试命令
```bash
# 查看事件
kubectl get events -n app-develop --sort-by=.metadata.creationTimestamp

# 查看部署历史
kubectl rollout history deployment/backend-first-app -n app-develop

# 查看服务端点
kubectl get endpoints -n app-develop

# 查看 ingress 状态
kubectl get ingress -n app-develop
```

## 🔧 扩展指南

### 添加新应用

1. **创建 K8s 配置文件**
   ```bash
   # 复制现有配置文件
   cp k8s/backend-first-app.yaml k8s/backend-third-app.yaml

   # 修改配置文件中的应用名称和端口
   # 将 "backend-first-app" 替换为 "backend-third-app"
   # 修改相应的端口号
   ```

2. **更新分支解析脚本**（如果需要特殊端口）
   ```bash
   # 编辑 scripts/parse-branch.sh
   # 在端口映射逻辑中添加新应用的端口配置
   ```

### 添加新环境

1. **更新分支解析脚本**
   ```bash
   # 编辑 scripts/parse-branch.sh
   # 在正则表达式中添加新环境
   # 在环境配置映射中添加新环境的配置
   ```

2. **创建对应的 namespace**
   ```bash
   kubectl create namespace app-newenv
   ```

## 📊 监控与日志

### 应用监控
- **Pod 状态**: 通过 `kubectl get pods` 查看
- **资源使用**: `kubectl top pods -n <namespace>`
- **日志查看**: `kubectl logs -f <pod-name> -n <namespace>`

### 健康检查
- **后端应用**: `/ping` 端点
- **前端应用**: `/health` 端点
- **存活探针**: 30秒后开始，每10秒检查一次
- **就绪探针**: 5秒后开始，每5秒检查一次

## 🔒 安全考虑

1. **Secret 管理**: 敏感信息使用 K8s Secret 存储
2. **网络隔离**: 不同环境使用不同 namespace
3. **镜像安全**: 使用私有镜像仓库，镜像签名验证
4. **访问控制**: 使用 RBAC 控制 K8s 访问权限

## 📚 相关文档

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [Docker 官方文档](https://docs.docker.com/)

---

## 🎯 总结

本方案实现了：
- ✅ 统一的分支命名规范
- ✅ 自动化的 CI/CD 流程
- ✅ 环境隔离和配置管理
- ✅ 可靠的版本管理和回滚机制
- ✅ 完善的监控和日志系统
- ✅ 简单易用的操作脚本

通过这套系统，可以轻松管理多个应用在多个环境中的部署，大大提高了开发和运维效率。