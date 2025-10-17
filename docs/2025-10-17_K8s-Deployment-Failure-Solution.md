# Kubernetes 自动部署失败问题解决方案

**环境**: Win11+WSL2+Docker Desktop
**问题时间**: 2025-10-17
**问题分支**: develop-backend-first-app

## 🔍 问题分析

### 核心问题识别
1. **API Server连接失败**: `localhost:8080` 连接被拒绝
2. **KUBECONFIG配置错误**: GitHub Actions使用了错误的In-Cluster配置
3. **Ingress Controller冲突**: 配置使用nginx，但集群运行Traefik
4. **Traefik端口冲突**: 多个服务争夺相同端口

### 根本原因
```bash
❌ 错误配置:
- GitHub Actions使用了In-Cluster配置 (export KUBECONFIG="")
- 导致kubectl尝试连接localhost:8080
- 实际API Server地址: kubernetes.docker.internal:6443

❌ Ingress冲突:
- YAML配置: nginx.ingress.kubernetes.io/*
- 实际运行: Traefik v2 (IngressRoute CRD)
```

## ✅ 解决方案实施

### 1. 修复GitHub Actions工作流配置

**文件**: `.github/workflows/deploy-monorepo.yaml`

**修改前**:
```yaml
else
  echo "🔧 使用In-Cluster配置..."
  export KUBECONFIG=""
  echo "✅ In-Cluster配置启用"
fi
```

**修改后**:
```yaml
else
  echo "🔧 使用Docker Desktop Kubeconfig..."
  export KUBECONFIG="$HOME/.kube/config"
  echo "✅ Docker Desktop Kubeconfig配置启用"
fi
```

### 2. 统一Ingress Controller配置

**修改文件**: `deploy/k8s/backend-first-app.yaml`

**删除nginx Ingress**:
```yaml
# ❌ 删除这部分
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
```

**添加Traefik IngressRoute**:
```yaml
# ✅ 添加Traefik配置
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: backend-first-app-ingress
  namespace: ${NAMESPACE}
spec:
  entryPoints:
    - web
  routes:
  - match: PathPrefix(`/backend-first-app`)
    kind: Rule
    services:
    - name: backend-first-app-service
      port: 80
    middlewares:
    - name: backend-first-app-stripprefix

---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: backend-first-app-stripprefix
  namespace: ${NAMESPACE}
spec:
  stripPrefix:
    prefixes:
      - /backend-first-app
    forceSlash: false
```

### 3. 清理旧的冲突资源

```bash
# 删除旧的nginx ingress
kubectl delete ingress backend-first-app-ingress -n backend-first-app

# 验证Traefik正常运行
kubectl get pods -n traefik
kubectl get svc -n traefik
```

## 🎯 验证步骤

### 1. 验证kubectl连接
```bash
kubectl cluster-info
# 应该显示: https://kubernetes.docker.internal:6443
```

### 2. 验证Traefik配置
```bash
kubectl get ingressroute -A
kubectl get middleware -A
```

### 3. 重新测试部署
```bash
# 手动测试部署脚本
./scripts/deploy.sh first-app develop

# 或通过GitHub Actions触发自动部署
git commit --allow-empty -m "test deployment fix"
git push origin develop-backend-first-app
```

## 📊 预期结果

### 部署成功后访问地址
- **后端应用**: http://localhost/backend-first-app/ping
- **前端应用**: http://localhost/ (如果配置了)
- **Traefik Dashboard**: http://localhost:8080/dashboard/

### K8s资源状态
```bash
# Pod状态
kubectl get pods -n backend-first-app
# NAME                                       READY   STATUS    RESTARTS   AGE
# backend-first-app-7be5617-xyzabc           1/1     Running   0          2m

# Service状态
kubectl get svc -n backend-first-app
# NAME                             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
# backend-first-app-service        ClusterIP   10.108.1.100    <none>        80/TCP    2m

# IngressRoute状态
kubectl get ingressroute -n backend-first-app
# NAME                           AGE
# backend-first-app-ingress      2m
```

## 🛠️ 故障排除命令

### 常用调试命令
```bash
# 查看pod日志
kubectl logs -n backend-first-app deployment/backend-first-app

# 查看事件
kubectl get events -n backend-first-app --sort-by=.metadata.creationTimestamp

# 查看资源详情
kubectl describe pod -n backend-first-app -l app=backend-first-app

# 端口转发测试
kubectl port-forward -n backend-first-app svc/backend-first-app-service 8080:80
```

### 常见问题处理
1. **镜像拉取失败**: 检查镜像标签和构建过程
2. **端口冲突**: 确认没有其他服务占用相同端口
3. **权限问题**: 检查RBAC配置和service account权限

## 📋 检查清单

- [ ] GitHub Actions工作流配置已修复
- [ ] Ingress Controller配置统一为Traefik
- [ ] 旧的nginx ingress资源已清理
- [ ] kubectl连接正常 (`kubectl cluster-info`)
- [ ] Traefik pod运行正常
- [ ] 应用部署成功
- [ ] 健康检查通过
- [ ] 外部访问测试正常

## 🔄 持续改进建议

1. **配置验证**: 在CI/CD中添加配置文件验证步骤
2. **环境隔离**: 确保不同环境使用不同的命名空间
3. **监控告警**: 配置Prometheus监控和告警规则
4. **自动化测试**: 添加部署后的自动化健康检查
5. **回滚机制**: 完善自动回滚流程

## 📝 总结

本次问题的核心是**环境配置不匹配**：
- GitHub Actions运行在WSL中，不在K8s集群内
- Ingress Controller配置与实际运行组件不符
- 端口配置冲突导致服务启动失败

通过统一配置和正确的环境设置，部署流程现在应该能够正常工作。