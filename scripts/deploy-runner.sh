#!/bin/bash

# GitHub Runner 修复部署脚本
# 用于部署持久化的GitHub Runner

set -e

echo "🚀 开始部署修复后的GitHub Runner"
echo "=================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 命名空间
NAMESPACE="github-runners"

echo -e "${BLUE}📋 检查当前环境...${NC}"

# 1. 检查命名空间
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  命名空间 $NAMESPACE 不存在，正在创建...${NC}"
    kubectl create namespace $NAMESPACE
else
    echo -e "${GREEN}✅ 命名空间 $NAMESPACE 已存在${NC}"
fi

# 2. 检查现有的Runner
echo -e "${BLUE}🔍 检查现有Runner状态...${NC}"
kubectl get pods -n $NAMESPACE -l app=github-runner --ignore-not-found=true

if kubectl get pods -n $NAMESPACE -l app=github-runner 2>/dev/null | grep -q "Running\|CrashLoopBackOff"; then
    echo -e "${YELLOW}⚠️  发现现有Runner，建议先备份配置${NC}"
    echo "是否要停止现有Runner？(y/N)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "${YELLOW}🛑 停止现有Runner...${NC}"
        kubectl scale deployment github-runner --replicas=0 -n $NAMESPACE || true
    fi
fi

# 3. 部署新的配置
echo -e "${BLUE}🚀 部署新的持久化Runner配置...${NC}"

echo "应用PVC配置..."
kubectl apply -f github-runner-fixed.yaml -n $NAMESPACE

echo -e "${GREEN}✅ 配置应用完成${NC}"

# 4. 等待PVC创建
echo -e "${BLUE}⏳ 等待PVC创建...${NC}"
kubectl wait --for=condition=Ready pvc/github-runner-state-pvc -n $NAMESPACE --timeout=60s || {
    echo -e "${YELLOW}⚠️  PVC创建超时，但继续部署${NC}"
}

# 5. 部署新的Runner
echo -e "${BLUE}🚀 部署新的Runner...${NC}"
kubectl apply -f github-runner-fixed.yaml -n $NAMESPACE

# 6. 等待新Pod启动
echo -e "${BLUE}⏳ 等待新Pod启动...${NC}"
kubectl rollout status deployment/github-runner-fixed -n $NAMESPACE --timeout=120s

# 7. 显示状态
echo -e "${BLUE}📊 新Runner状态：${NC}"
kubectl get pods -n $NAMESPACE -l component=runner-fixed -o wide

# 8. 获取Pod名称
POD_NAME=$(kubectl get pods -n $NAMESPACE -l component=runner-fixed -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    echo -e "${GREEN}✅ 新Pod已启动: $POD_NAME${NC}"

    # 9. 显示日志
    echo -e "${BLUE}📝 显示启动日志（最后20行）：${NC}"
    kubectl logs -n $NAMESPACE "$POD_NAME" --tail=20

    # 10. 监控状态
    echo -e "${BLUE}🔍 监控Runner状态（按Ctrl+C停止）...${NC}"
    echo "等待Runner注册到GitHub..."

    # 持续监控Pod状态
    while true; do
        POD_STATUS=$(kubectl get pod "$POD_NAME" -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "$(date '+%H:%M:%S') - Pod状态: $POD_STATUS"

        if [ "$POD_STATUS" = "Running" ]; then
            echo -e "${GREEN}✅ Pod正在运行，检查Runner状态...${NC}"

            # 检查是否有进程在运行
            if kubectl exec -n $NAMESPACE "$POD_NAME" -- pgrep -f "Runner.Listener" > /dev/null 2>&1; then
                echo -e "${GREEN}🎉 Runner服务已启动！${NC}"
                echo ""
                echo -e "${BLUE}📋 下一步操作：${NC}"
                echo "1. 访问 https://github.com/gszw90/k8s-app/settings/actions/runners"
                echo "2. 检查Runner是否显示为 'Idle' 状态"
                echo "3. 如果未显示，请检查日志中的错误信息"
                echo ""
                echo -e "${BLUE}🔧 查看完整日志：${NC}"
                echo "kubectl logs -f -n $NAMESPACE $POD_NAME"
                echo ""
                echo -e "${BLUE}🔄 重启Runner（如果需要）：${NC}"
                echo "kubectl delete pod -n $NAMESPACE $POD_NAME"
                break
            fi
        fi

        sleep 10
    done
else
    echo -e "${RED}❌ 无法获取新Pod名称${NC}"
    echo "请检查部署状态："
    kubectl get all -n $NAMESPACE
    exit 1
fi

echo -e "${GREEN}🎉 部署脚本执行完成！${NC}"
echo ""
echo -e "${YELLOW}⚠️  重要提醒：${NC}"
echo "1. 如果Runner无法注册，请按照 github-token-renewal-guide.md 重新生成Token"
echo "2. 确保在GitHub中可以看到Runner状态为 'Idle'"
echo "3. 测试推送代码到 develop-backend-first-app 分支验证工作流程"