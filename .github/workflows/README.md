# GitHub Actions Workflows for Local K8s CI/CD

这个目录包含了用于本地 Kubernetes CI/CD 的 GitHub Actions 工作流文件。

## 📁 Workflow 文件说明

### 1. `local-k8s-deploy.yaml` - 通用部署工作流
**功能**: 支持所有项目和环境的完整 CI/CD 流程

**触发分支**:
- `*-develop` (所有项目的开发环境)
- `*-staging` (所有项目的测试环境)
- `*-prod` (所有项目的生产环境)

**支持的分支命名规范**:
```
backend-first-app-develop
backend-first-app-staging
backend-first-app-prod
backend-second-app-develop
frontend-web-develop
frontend-web-staging
frontend-web-prod
```

**特点**:
- ✅ 自动解析分支名称获取项目和环
- ✅ Docker 镜像构建和标签管理
- ✅ K8s 部署和健康检查
- ✅ 自动端点测试
- ✅ 镜像清理（保留最新5个）
- ✅ 手动触发支持

### 2. `deploy-backend-enhanced.yaml` - 后端专用工作流
**功能**: 专门针对后端服务的部署

**触发分支**:
- `backend-first-app-*`
- `backend-second-app-*`

**特点**:
- ✅ 针对后端服务优化的测试
- ✅ `/ping` 和 `/hello` 端点测试
- ✅ 手动触发支持，可选择项目和环境

### 3. `deploy-frontend.yaml` - 前端专用工作流
**功能**: 专门针对前端服务的部署

**触发分支**:
- `frontend-web-*`

**特点**:
- ✅ 前端服务专用配置
- ✅ 根路径和 `/health` 端点测试
- ✅ 环境变量管理

### 4. `deploy-backend.yaml` - 原始工作流（保留）
**功能**: 原始的后端部署工作流，建议使用 `deploy-backend-enhanced.yaml` 替代

## 🚀 使用指南

### 自动部署（推送触发）

1. **创建符合命名规范的分支**:
   ```bash
   # 创建 first-app 开发环境分支
   git checkout -b backend-first-app-develop

   # 创建 web 前端测试环境分支
   git checkout -b frontend-web-staging
   ```

2. **推送代码到对应分支**:
   ```bash
   git add .
   git commit -m "feat: add new feature"
   git push origin backend-first-app-develop
   ```

3. **GitHub Actions 会自动触发**:
   - 解析分支信息
   - 构建 Docker 镜像
   - 部署到本地 K8s
   - 运行健康检查

### 手动部署

1. **进入 GitHub Actions 页面**
2. **选择对应的工作流**
3. **点击 "Run workflow"**
4. **选择环境和项目**（如果支持）

### 监控部署状态

1. **查看 GitHub Actions 日志**
2. **检查本地 K8s 状态**:
   ```bash
   # 查看所有 pods
   kubectl get pods -n app

   # 查看特定环境的部署
   kubectl get pods -n app -l environment=develop

   # 查看服务
   kubectl get services -n app

   # 查看入口
   kubectl get ingress -n app
   ```

3. **测试部署的服务**:
   ```bash
   # 测试后端服务
   curl http://first-app-develop.localhost/ping
   curl http://second-app-develop.localhost/hello

   # 测试前端服务
   curl http://web-develop.localhost/
   curl http://web-develop.localhost/health
   ```

## 🌐 服务访问地址

部署完成后，可以通过以下地址访问服务：

### 开发环境 (develop)
- **First App**: http://first-app-develop.localhost
- **Second App**: http://second-app-develop.localhost
- **Web App**: http://web-develop.localhost

### 测试环境 (staging)
- **First App**: http://first-app-staging.localhost
- **Second App**: http://second-app-staging.localhost
- **Web App**: http://web-staging.localhost

### 生产环境 (prod)
- **First App**: http://first-app-prod.localhost
- **Second App**: http://second-app-prod.localhost
- **Web App**: http://web-prod.localhost

## 🔧 故障排除

### 常见问题

1. **K8s 连接失败**:
   ```bash
   kubectl cluster-info
   # 确保集群运行正常
   ```

2. **Docker 镜像构建失败**:
   - 检查 Dockerfile 路径
   - 确保所有文件都在正确的位置

3. **部署超时**:
   ```bash
   # 检查 pod 状态
   kubectl describe pod <pod-name> -n app

   # 查看日志
   kubectl logs <pod-name> -n app
   ```

4. **端点测试失败**:
   - 检查服务是否正确启动
   - 验证端口配置
   - 确认网络策略

### 清理和重置

```bash
# 删除特定部署
kubectl delete deployment/app-first-app-develop -n app

# 清理所有部署
kubectl delete all --all -n app

# 清理本地 Docker 镜像
docker system prune -f
```

## 📝 注意事项

1. **Self-hosted Runner**: 确保 self-hosted runner 有访问 Docker 和 K8s 的权限
2. **网络配置**: 确保本地 DNS 配置支持 `.localhost` 域名解析
3. **资源限制**: 监控本地资源使用情况，避免资源耗尽
4. **安全考虑**: 本地部署仅用于开发和学习，不适合生产环境
5. **范围控制**: 避免不必要的修改，每次只修改必要的文件，不要扩散修改范围

## 🔄 工作流自定义

你可以根据需要修改工作流文件：

- **调整超时时间**: 修改 `timeout` 参数
- **添加测试步骤**: 在部署后添加自定义测试
- **通知配置**: 添加 Slack、邮件等通知
- **环境变量**: 根据需要添加自定义环境变量