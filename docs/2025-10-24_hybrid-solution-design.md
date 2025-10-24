# 混合解决方案设计：GitHub App + 自动化Runner管理

## 🎯 方案概述

由于网络限制无法直接部署完整的Actions Runner Controller，设计一个混合解决方案，结合GitHub App认证和自动化脚本管理，实现与ARC类似的效果。

## 🏗️ 架构设计

### 混合架构图
```
GitHub App (长期有效)
    ↓ (自动token生成)
定时任务/CronJob
    ↓ (token更新)
Kubernetes CronJob
    ↓ (自动重启runner)
现有Runner Deployment
    ↓ (自动扩展)
CI/CD Workflows
```

### 核心组件
1. **GitHub App认证** - 使用现有的runner-ci-cd App进行长期有效认证
2. **自动Token管理** - 定时任务自动更新runner token
3. **智能Runner管理** - 基于workload动态调整runner数量
4. **监控和告警** - 全面的状态监控和故障通知

## 🔧 技术实现

### 1. GitHub App Token自动生成

#### Token生成脚本增强
```bash
#!/bin/bash
# 使用GitHub App自动生成runner token
# 替代之前的手动token更新

# GitHub App配置
APP_ID="2168366"
INSTALLATION_ID="91349326"
PRIVATE_KEY_FILE="./github-app-private-key.pem"

# 生成JWT Token
JWT_TOKEN=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
echo "Generated JWT: $JWT_TOKEN"

# 使用GitHub CLI获取App Access Token
APP_ACCESS_TOKEN=$(gh auth token --app "$APP_ID" --installation "$INSTALLATION_ID")

# 生成runner registration token
RUNNER_TOKEN=$(gh api --method POST \
    -H "Authorization: token $APP_ACCESS_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "/repos/gszw90/k8s-app/actions/runners/registration-token" | \
    jq -r '.token')
```

### 2. Kubernetes CronJob自动更新

#### 定时Token更新CronJob
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: runner-token-updater
  namespace: github-runners
spec:
  schedule: "0 */2 * * *"  # 每2小时执行一次
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: token-updater
            image: alpine/git:latest
            command:
            - /bin/sh
            - -c
            - |
              # 安装必要工具
              apk add --no-cache curl jq

              # 下载并执行token更新脚本
              curl -s https://raw.githubusercontent.com/gszw90/k8s-app/main/scripts/update-runner-token-github-app.sh | sh

              # 重启runner deployment
              kubectl rollout restart deployment/github-runner-simple -n github-runners
          restartPolicy: OnFailure
```

### 3. 智能Runner扩展

#### 基于队列长度的自动扩展
```bash
#!/bin/bash
# 智能runner扩展脚本

# 检查GitHub Actions队列状态
check_queue_status() {
    local queue_length=$(gh api /repos/gszw90/k8s-app/actions/runs \
        --jq '.workflow_runs | map(select(.status == "queued")) | length')

    echo "当前队列长度: $queue_length"
    return $queue_length
}

# 动态调整runner数量
scale_runners() {
    local queue_length=$1
    local current_replicas=$(kubectl get deployment github-runner-simple -n github-runners -o jsonpath='{.spec.replicas}')

    local desired_replicas

    if [ $queue_length -eq 0 ]; then
        desired_replicas=0  # 队列为空，收缩到0
    elif [ $queue_length -le 2 ]; then
        desired_replicas=1  # 少量任务，1个runner
    elif [ $queue_length -le 5 ]; then
        desired_replicas=2  # 中等任务，2个runner
    else
        desired_replicas=3  # 大量任务，3个runner
    fi

    if [ $desired_replicas -ne $current_replicas ]; then
        echo "扩展runner: $current_replicas → $desired_replicas"
        kubectl scale deployment github-runner-simple --replicas=$desired_replicas -n github-runners
    fi
}

# 主逻辑
queue_length=$(check_queue_status)
scale_runners $queue_length
```

### 4. 监控和告警系统

#### Prometheus监控指标
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: runner-monitoring-config
  namespace: github-runners
data:
  monitoring.yml: |
    jobs:
      - name: runner-status
        schedule: "*/5 * * * *"
        script: |
          # 检查runner状态
          kubectl get pods -n github-runners -l app=github-runner

          # 检查token有效性
          ./scripts/check-token-validity.sh

          # 发送告警（如需要）
          if [ $? -ne 0 ]; then
            send_alert "Runner token需要更新"
          fi
```

## 📊 实施优势

### 相比完整ARC方案
- ✅ **部署简单** - 无需复杂CRD和Controller
- ✅ **快速见效** - 基于现有runner部署改进
- ✅ **可控性强** - 完全自主可控的脚本逻辑
- ✅ **渐进升级** - 后续可平滑迁移到完整ARC

### 解决的核心问题
- ✅ **Token过期** - GitHub App长期有效，自动更新
- ✅ **资源浪费** - 基于队列长度动态扩展
- ✅ **运维复杂** - 完全自动化的token和runner管理
- ✅ **监控缺失** - 全面的状态监控和告警

## 🚀 实施计划

### 阶段1: GitHub App集成 (当前)
1. ✅ GitHub App配置分析完成
2. ✅ 私钥文件已创建
3. 🔄 开发GitHub App token生成脚本
4. 📋 测试GitHub App认证流程

### 阶段2: 自动化部署 (接下来)
1. 📋 创建token更新CronJob
2. 📋 实现智能扩展脚本
3. 📋 部署监控系统
4. 📋 集成告警通知

### 阶段3: 优化和验证 (后续)
1. 📋 性能调优和测试
2. 📋 多环境支持
3. 📋 文档完善
4. 📋 团队培训

## 📁 实施文件清单

### 新增文件
- `scripts/update-runner-token-github-app.sh` - GitHub App token更新脚本
- `scripts/smart-runner-scaler.sh` - 智能runner扩展脚本
- `scripts/monitor-runner-health.sh` - 健康检查脚本
- `deploy/k8s/runner-token-updater-cronjob.yaml` - 定时更新任务
- `deploy/k8s/runner-monitoring-config.yaml` - 监控配置

### 更新文件
- `CLAUDE.md` - 更新项目文档
- `.github/workflows/deploy-backend.yaml` - 更新workflow配置

## 🔍 监控和维护

### 关键指标
- Token更新成功率
- Runner响应时间
- 队列处理速度
- 资源使用率

### 告警规则
- Token更新失败
- Runner pod异常
- 队列积压超过阈值
- 资源使用异常

## 🎯 预期效果

### 短期效果 (1-2周)
- ✅ 彻底解决token过期问题
- ✅ 实现70%以上的自动化程度
- ✅ 减少50%的运维工作量

### 长期效果 (1-3月)
- ✅ 运维成本降低60-70%
- ✅ CI/CD稳定性提升90%+
- ✅ 支持更大规模的工作负载

## 🔄 升级路径

### 向完整ARC迁移
1. **并行运行** - 混合方案与ARC同时运行
2. **逐步切换** - 将部分环境迁移到ARC
3. **全面迁移** - 完全切换到ARC管理
4. **清理旧系统** - 移除混合方案组件

---

**方案状态**: 🔄 设计完成，开始实施
**优先级**: 🟢 高优先级 (解决当前关键问题)
**风险等级**: 🟡 中等风险 (需要充分测试)
**预期完成**: 1-2周内完成核心功能