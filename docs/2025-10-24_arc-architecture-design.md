# Actions Runner Controller (ARC) 架构设计方案

## 🎯 解决方案概述

基于 GitHub App (runner-ci-cd) + Actions Runner Controller 的新架构，完全解决现有的 token 管理和 runner 生命周期问题。

## 📊 GitHub App 集成分析

### 当前配置优势
```yaml
AppName: runner-ci-cd
AppId: 2168366
ClientId: Iv23lizdOiISiUHCD7of
InstallationId: 91349326
```

**与 ARC 集成的完美匹配**:
- ✅ **长期有效认证**: 无1小时过期限制
- ✅ **多租户支持**: 可管理多个仓库/组织的runner
- ✅ **细粒度权限**: 只授予必要的最小权限
- ✅ **审计追踪**: GitHub提供完整的App操作日志

### ARC认证配置
```bash
kubectl create secret generic controller-manager \
    -n actions-runner-system \
    --from-literal=github_app_id=2168366 \
    --from-literal=github_app_installation_id=91349326 \
    --from-file=github_app_private_key=./private-key.pem
```

## 🏗️ 方向B：ARC部署架构设计

### 核心架构对比

#### 当前架构 (手动管理)
```
GitHub (1hr token) → Runner Pod (固定数量) → CI/CD Jobs
         ↓
   Token过期 → CrashLoopBackOff → 手动重启
```

#### 新架构 (ARC自动管理)
```
GitHub App (长期有效) → ARC Controller → 动态Runner池 → CI/CD Jobs
         ↓                    ↓
   无过期问题           自动扩展/收缩
```

### 多环境Runner管理策略

#### 1. 命名空间隔离
```yaml
environments:
  develop:    actions-runners-develop
  staging:    actions-runners-staging
  prod:       actions-runners-prod
```

#### 2. 自动扩展配置
```yaml
# 开发环境：快速扩展，快速收缩
- minReplicas: 0
- maxReplicas: 5
- scaleUpTriggers: workflow_job

# 生产环境：稳定运行，适度扩展
- minReplicas: 2
- maxReplicas: 10
- scaleUpTriggers: workflow_job
```

## 🚀 技术实现路径

### 阶段1：ARC Controller 部署
```bash
# 1. 创建namespace
kubectl create namespace actions-runner-system

# 2. 配置GitHub App认证secret
kubectl create secret generic controller-manager \
  -n actions-runner-system \
  --from-literal=github_app_id=2168366 \
  --from-literal=github_app_installation_id=91349326 \
  --from-file=github_app_private_key=./github-app-private-key.pem

# 3. 安装ARC Controller
helm repo add actions-runner-controller \
  https://actions-runner-controller.github.io/actions-runner-controller

helm upgrade --install --namespace actions-runner-system \
  actions-runner-controller actions-runner-controller/actions-runner-controller \
  --set authSecret.create=false \
  --set authSecret.name=controller-manager
```

### 阶段2：Runner资源定义
```yaml
# RunnerDeployment (开发环境)
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: develop-runner
  namespace: actions-runners-develop
spec:
  replicas: 0  # 初始为0，由HRA自动扩展
  template:
    spec:
      repository: gszw90/k8s-app
      githubAPICredentialsFrom:
        secretRef:
          name: controller-manager
          namespace: actions-runner-system

---
# HorizontalRunnerAutoscaler (自动扩展)
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: develop-hra
  namespace: actions-runners-develop
spec:
  scaleTargetRef:
    name: develop-runner
  minReplicas: 0
  maxReplicas: 5
  scaleUpTriggers:
  - githubEvent:
      workflowJob: {}
    duration: "30m"
```

## 📈 性能和成本优势

### 解决的核心问题

#### 1. Token管理问题
- **❌ 当前**: 1小时过期，需要手动更新token
- **✅ 新方案**: GitHub App长期有效，自动管理认证

#### 2. Runner生命周期管理
- **❌ 当前**: 固定数量runner，资源浪费
- **✅ 新方案**: 根据workload自动扩展/收缩

#### 3. 运维复杂度
- **❌ 当前**: 手动维护，故障处理复杂
- **✅ 新方案**: ARC自动处理健康检查和重启

#### 4. 多环境支持
- **❌ 当前**: 单一环境配置，难以扩展
- **✅ 新方案**: 多命名空间，独立管理

### 成本优化估算
```
当前方案: 24小时运行 × 3个环境 × 2个runner = 144 runner小时/天
新方案:   实际使用时间 × 按需扩展 ≈ 40-60 runner小时/天

节省: 60-70% 的运行成本
```

## 🔧 迁移策略

### 平滑迁移步骤

#### 1. 并行运行期 (1-2周)
- 保持现有runner运行
- 部署ARC和新runner池
- 逐步将测试工作负载迁移到新runner

#### 2. 验证期 (1周)
- 全面测试CI/CD流水线
- 验证自动扩展功能
- 监控性能和稳定性

#### 3. 切换期 (1-2天)
- 停用旧runner
- 全面切换到ARC管理的runner
- 清理旧资源和配置

### 回滚计划
```bash
# 如果需要回滚，快速重新部署旧runner
kubectl apply -f deploy/k8s/github-runner.yaml
```

## 🛡️ 安全性增强

### 权限最小化
- GitHub App只授予必要的仓库权限
- ServiceAccount权限精细化控制
- 多命名空间隔离降低风险

### 审计和监控
- GitHub App操作完整审计日志
- Kubernetes事件监控
- Runner状态实时监控

## 📋 实施检查清单

### 准备工作
- [ ] 验证GitHub App权限范围
- [ ] 备份当前runner配置
- [ ] 准备私钥文件
- [ ] 创建目标命名空间

### 部署步骤
- [ ] 部署ARC Controller
- [ ] 配置GitHub App认证
- [ ] 创建RunnerDeployment资源
- [ ] 配置自动扩展规则
- [ ] 测试CI/CD流水线

### 验证测试
- [ ] 验证runner自动扩展
- [ ] 测试多环境隔离
- [ ] 验证权限配置
- [ ] 性能基准测试

### 清理工作
- [ ] 停用旧runner
- [ ] 清理临时资源
- [ ] 更新文档
- [ ] 团队培训

---

**方案优势总结**:
1. ✅ **彻底解决token过期问题** - GitHub App长期有效认证
2. ✅ **大幅降低运维成本** - 自动化runner生命周期管理
3. ✅ **提升资源利用效率** - 按需扩展，避免资源浪费
4. ✅ **增强系统稳定性** - 自动故障恢复和健康检查
5. ✅ **支持未来扩展** - 多租户架构，易于扩展