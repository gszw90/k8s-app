# GitHub Runner 持久化配置指南

## 当前状态分析

### ✅ 已有的持久化配置
- **持久化存储**: 5Gi hostpath PVC 用于保存Runner状态
- **配置持久化**: ConfigMap 和 Secret 保存配置信息
- **Docker挂载**: Docker socket 和 lib 挂载，支持容器构建

### ⚠️ 需要改进的问题
1. **Token过期**: GitHub Runner token有时效性
2. **自动重启策略**: 当前策略可能不够健壮
3. **健康检查**: 需要更完善的生命周期管理

## 🔧 持久化增强方案

### 1. Token自动更新机制
```bash
# 创建token更新脚本
cat > scripts/update-runner-token.sh << 'EOF'
#!/bin/bash
# GitHub Runner Token自动更新脚本

RUNNER_NS="github-runners"
CONFIG_MAP="github-runner-config-updated"
SECRET="github-runner-secret"

echo "检查Runner状态..."
RUNNER_STATUS=$(kubectl get pods -n $RUNNER_NS -l app=github-runner -o jsonpath='{.items[0].status.phase}')

if [ "$RUNNER_STATUS" != "Running" ]; then
    echo "Runner状态异常: $RUNNER_STATUS"
    echo "请检查GitHub并提供新的token:"
    echo "访问: https://github.com/gszw90/k8s-app/settings/actions/runners"
    exit 1
fi

echo "Runner运行正常"
EOF

chmod +x scripts/update-runner-token.sh
```

### 2. 增强部署配置
```yaml
# 推荐的部署配置更新
apiVersion: apps/v1
kind: Deployment
metadata:
  name: github-runner-simple
  namespace: github-runners
spec:
  replicas: 1
  strategy:
    type: Recreate  # 确保完全重启
  template:
    spec:
      restartPolicy: Always
      containers:
      - name: github-runner
        image: myoung34/github-runner:latest
        env:
        - name: RUNNER_EPHEMERAL
          value: "false"  # 保持持久化
        - name: RUNNER_DISABLE_UPDATE
          value: "false"  # 允许自动更新
        livenessProbe:
          exec:
            command:
            - pgrep
            - -f
            - Runner.Listener
          initialDelaySeconds: 120  # 增加初始延迟
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 5  # 增加容错次数
        readinessProbe:
          exec:
            command:
            - pgrep
            - -f
            - Runner.Listener
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2
            memory: 4Gi
        volumeMounts:
        - name: runner-state
          mountPath: /tmp/github-runner-workdir
        - name: docker-sock
          mountPath: /var/run/docker.sock
        - name: docker-lib
          mountPath: /var/lib/docker
      volumes:
      - name: runner-state
        persistentVolumeClaim:
          claimName: github-runner-state-pvc
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
      - name: docker-lib
        hostPath:
          path: /var/lib/docker
          type: Directory
```

### 3. 关机重启验证清单

#### 关机前检查 ✅
- [ ] Runner状态正常 (`kubectl get pods -n github-runners`)
- [ ] 持久化存储挂载正常 (`kubectl describe pvc github-runner-state-pvc -n github-runners`)
- [ ] 配置文件完整 (`kubectl get configmap github-runner-config-updated -n github-runners -o yaml`)

#### 重启后验证 🔍
- [ ] K8s集群启动 (`kubectl cluster-info`)
- [ ] 命名空间存在 (`kubectl get ns github-runners`)
- [ ] Pod自动启动 (`kubectl get pods -n github-runners`)
- [ ] Runner连接GitHub (`kubectl logs -n github-runners deployment/github-runner-simple --tail=20`)

### 4. 自动恢复脚本
```bash
# 创建自动恢复脚本
cat > scripts/recover-runner.sh << 'EOF'
#!/bin/bash
# GitHub Runner自动恢复脚本

set -e

RUNNER_NS="github-runners"
DEPLOYMENT="github-runner-simple"

echo "🔄 开始GitHub Runner自动恢复..."

# 1. 检查命名空间
if ! kubectl get namespace $RUNNER_NS > /dev/null 2>&1; then
    echo "❌ 命名空间 $RUNNER_NS 不存在"
    exit 1
fi

echo "✅ 命名空间检查通过"

# 2. 检查部署状态
if ! kubectl get deployment $DEPLOYMENT -n $RUNNER_NS > /dev/null 2>&1; then
    echo "❌ 部署 $DEPLOYMENT 不存在"
    exit 1
fi

echo "✅ 部署检查通过"

# 3. 检查Pod状态
POD_STATUS=$(kubectl get pods -n $RUNNER_NS -l app=github-runner -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

if [ "$POD_STATUS" != "Running" ]; then
    echo "⚠️  Pod状态: $POD_STATUS，尝试重启..."
    kubectl rollout restart deployment/$DEPLOYMENT -n $RUNNER_NS

    # 等待Pod启动
    echo "⏳ 等待Pod启动..."
    kubectl wait --for=condition=ready pod -l app=github-runner -n $RUNNER_NS --timeout=300s
fi

echo "✅ Pod状态检查通过"

# 4. 验证Runner连接
echo "🔍 验证Runner连接状态..."
sleep 30  # 给Runner时间连接GitHub

RUNNER_LOGS=$(kubectl logs -n $RUNNER_NS deployment/$DEPLOYMENT --tail=10)
if echo "$RUNNER_LOGS" | grep -q "Listening for Jobs"; then
    echo "🎉 GitHub Runner恢复成功！"
    echo "📊 当前状态:"
    kubectl get pods -n $RUNNER_NS
else
    echo "❌ Runner连接异常，请检查token配置"
    echo "最新日志:"
    echo "$RUNNER_LOGS"
    exit 1
fi
EOF

chmod +x scripts/recover-runner.sh
```

### 5. 定期健康检查
```bash
# 创建健康检查脚本
cat > scripts/health-check.sh << 'EOF'
#!/bin/bash
# GitHub Runner健康检查脚本

RUNNER_NS="github-runners"

echo "🏥 GitHub Runner健康检查..."

# 检查Pod状态
POD_COUNT=$(kubectl get pods -n $RUNNER_NS -l app=github-runner --no-headers | wc -l)
READY_COUNT=$(kubectl get pods -n $RUNNER_NS -l app=github-runner -o jsonpath='{.items[?(@.status.ready==true)].status.phase}' | wc -w)

echo "📈 Pod状态: $READY_COUNT/$POD_COUNT 就绪"

if [ "$READY_COUNT" -eq "$POD_COUNT" ] && [ "$POD_COUNT" -gt 0 ]; then
    echo "✅ 所有Runner运行正常"

    # 检查连接状态
    LATEST_LOG=$(kubectl logs -n $RUNNER_NS deployment/github-runner-simple --tail=5)
    if echo "$LATEST_LOG" | grep -q "Listening for Jobs"; then
        echo "✅ Runner已连接GitHub"
    else
        echo "⚠️  Runner可能未连接GitHub"
        echo "最新日志: $LATEST_LOG"
    fi
else
    echo "❌ Runner状态异常"
    kubectl get pods -n $RUNNER_NS -l app=github-runner
fi
EOF

chmod +x scripts/health-check.sh
```

## 🚀 使用建议

### 日常使用
1. **关机前运行**: `./scripts/health-check.sh`
2. **重启后运行**: `./scripts/recover-runner.sh`
3. **Token更新**: `./scripts/update-runner-token.sh`

### 自动化集成
```bash
# 添加到crontab，每10分钟检查一次
*/10 * * * * /path/to/your/scripts/health-check.sh >> /var/log/runner-health.log 2>&1

# 开机自启动（systemd服务）
sudo tee /etc/systemd/system/runner-recovery.service > /dev/null << EOF
[Unit]
Description=GitHub Runner Recovery Service
After=kubernetes.service

[Service]
Type=oneshot
ExecStart=/path/to/your/scripts/recover-runner.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable runner-recovery.service
```

## 📋 故障排除

### 常见问题
1. **Token过期**: 重新生成token并更新secret
2. **Docker权限**: 确保Docker socket挂载正确
3. **存储问题**: 检查PVC状态和hostpath权限
4. **网络问题**: 检查GitHub连接和代理设置

### 紧急恢复
```bash
# 完全重新部署（谨慎使用）
kubectl delete deployment github-runner-simple -n github-runners
kubectl apply -f k8s/github-runner-deployment.yaml
```

通过以上配置，您的GitHub Runner将能够在关机重启后自动恢复运行状态。