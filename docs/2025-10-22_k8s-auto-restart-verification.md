# GitHub Runner K8s自动重启验证指南

## 🎯 验证目标

确保GitHub Runner在K8s集群重启后能够自动恢复运行状态，无需人工干预。

## ✅ 当前自愈能力验证

### 1. 基础配置验证
```bash
# 验证命名空间
kubectl get namespace github-runners

# 验证部署状态
kubectl get deployment github-runner-simple -n github-runners

# 验证Pod运行状态
kubectl get pods -n github-runners -l app=github-runner
```

**预期结果：**
- ✅ 命名空间存在
- ✅ 部署可用 (AVAILABLE: True)
- ✅ Pod运行中 (STATUS: Running, READY: 1/1)

### 2. 健康检查验证
```bash
# 检查健康检查配置
kubectl describe pod -n github-runners -l app=github-runner | grep -A 5 "Liveness\|Readiness"

# 检查Pod条件状态
kubectl get pod -n github-runners -l app=github-runner -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'
```

**预期结果：**
- ✅ Liveness probe已配置 (delay=60s, period=30s)
- ✅ Readiness probe已配置 (delay=30s, period=10s)
- ✅ Pod条件状态为 True

### 3. 持久化验证
```bash
# 检查PVC状态
kubectl get pvc -n github-runners

# 检查存储挂载
kubectl describe pod -n github-runners -l app=github-runner | grep -A 10 "Volumes:"
```

**预期结果：**
- ✅ PVC状态为 Bound
- ✅ 存储卷正确挂载

## 🔄 K8s重启自动恢复流程

### 自动恢复机制
1. **K8s集群启动** → API Server可用
2. **命名空间恢复** → `github-runners` 自动加载
3. **配置恢复** → ConfigMap/Secret自动应用
4. **存储恢复** → PVC自动挂载到Pod
5. **部署恢复** → Deployment控制器创建新Pod
6. **容器启动** → Runner容器开始运行
7. **服务注册** → Runner向GitHub注册
8. **健康检查** → Probes验证服务可用

### 恢复时间预期
- **Pod启动**: 30-60秒
- **Runner注册**: 60-120秒
- **整体恢复**: 2-3分钟

## 🧪 验证测试方法

### 方法1: 模拟Pod删除
```bash
# 删除当前Pod，观察自动重建
kubectl delete pod -n github-runners -l app=github-runner

# 观察新Pod创建
watch kubectl get pods -n github-runners -l app=github-runner
```

### 方法2: 模拟部署重启
```bash
# 重启部署
kubectl rollout restart deployment/github-runner-simple -n github-runners

# 观察滚动更新
kubectl rollout status deployment/github-runner-simple -n github-runners
```

### 方法3: 检查自愈配置
```bash
# 检查Deployment自愈配置
kubectl get deployment github-runner-simple -n github-runners -o yaml | grep -A 10 "replicas\|restartPolicy\|strategy"

# 检查Pod重启策略
kubectl get pod -n github-runners -l app=github-runner -o jsonpath='{.items[0].spec.restartPolicy}'
```

## 📊 监控和日志

### 实时监控
```bash
# 监控Pod状态
watch -n 5 "kubectl get pods -n github-runners -l app=github-runner"

# 监控Runner日志
kubectl logs -f deployment/github-runner-simple -n github-runners

# 监控K8s事件
kubectl get events -n github-runners --sort-by='.lastTimestamp' | tail -10
```

### 成功指标
- ✅ Pod自动重建时间 < 2分钟
- ✅ Runner成功连接GitHub ("Listening for Jobs")
- ✅ 健康检查通过 (READY: 1/1)
- ✅ 无需人工干预

## 🚨 故障排除

### 常见问题和解决方案

#### 1. Pod无法启动
```bash
# 检查Pod错误
kubectl describe pod -n github-runners -l app=github-runner

# 检查镜像
kubectl get pod -n github-runners -l app=github-runner -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting}'
```

#### 2. Runner无法连接GitHub
```bash
# 检查token配置
kubectl get secret github-runner-secret -n github-runners -o yaml | grep RUNNER_TOKEN

# 检查Runner日志
kubectl logs -n github-runners deployment/github-runner-simple --tail=50
```

#### 3. 存储问题
```bash
# 检查PVC状态
kubectl get pvc -n github-runners -o wide

# 检查存储卷
kubectl get pv | grep github-runner
```

### 手动恢复步骤
如果自动恢复失败，可以手动执行：

```bash
# 1. 重启部署
kubectl rollout restart deployment/github-runner-simple -n github-runners

# 2. 等待Pod就绪
kubectl wait --for=condition=ready pod -l app=github-runner -n github-runners --timeout=300s

# 3. 验证Runner连接
kubectl logs -n github-runners deployment/github-runner-simple --tail=20 | grep "Listening for Jobs"
```

## 📋 验证清单

### K8s重启后验证清单 ✅

- [ ] **集群状态**: `kubectl cluster-info` 正常
- [ ] **命名空间**: `github-runners` 存在
- [ ] **部署状态**: Deployment AVAILABLE = True
- [ ] **Pod状态**: Pod Running, Ready = 1/1
- [ ] **健康检查**: Liveness/Readiness probes通过
- [ ] **存储挂载**: PVC Bound, 卷正确挂载
- [ ] **Runner连接**: 日志显示 "Listening for Jobs"
- [ ] **无错误事件**: 最近5分钟无error级别事件

### 性能指标验证
- [ ] **启动时间**: Pod从Pending到Running < 2分钟
- [ ] **恢复时间**: 整体服务恢复 < 5分钟
- [ ] **资源使用**: CPU/内存在正常范围内
- [ ] **重启次数**: 24小时内异常重启 < 3次

## 🎯 结论

通过以上验证，您的GitHub Runner部署已具备完整的K8s原生自愈能力：

1. **自动恢复**: K8s重启后Runner自动启动
2. **健康监控**: 持续监控Runner状态
3. **故障自愈**: 异常时自动重启重建
4. **持久化**: 配置和数据跨重启保持
5. **零干预**: 无需人工参与恢复过程

**您的GitHub Runner现在可以在K8s集群重启后完全自动恢复运行！** 🎉