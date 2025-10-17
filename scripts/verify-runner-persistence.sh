#!/bin/bash

# GitHub Actions Runner 持久化验证脚本
# 用于验证重启后 runner 状态的保持

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 GitHub Actions Runner 持久化验证${NC}"
echo "===================================="

# 获取当前 runner pod 信息
echo -e "${BLUE}📋 当前 Runner 状态:${NC}"
CURRENT_POD=$(kubectl get pods -n github-runners -l component=simple -o jsonpath='{.items[0].metadata.name}')
echo "Pod 名称: $CURRENT_POD"

# 检查工作目录内容
echo ""
echo -e "${BLUE}📂 工作目录内容:${NC}"
kubectl exec -n github-runners "$CURRENT_POD" -- ls -la /tmp/github-runner-workdir/

# 检查工作目录详细内容
echo ""
echo -e "${BLUE}📁 _work 目录内容:${NC}"
kubectl exec -n github-runners "$CURRENT_POD" -- ls -la /tmp/github-runner-workdir/_work/ || echo "目录为空（正常状态）"

# 检查 PVC 状态
echo ""
echo -e "${BLUE}💾 PVC 状态:${NC}"
kubectl get pvc -n github-runners github-runner-state-pvc

# 检查存储使用情况
echo ""
echo -e "${BLUE}📊 存储使用情况:${NC}"
kubectl exec -n github-runners "$CURRENT_POD" -- du -sh /tmp/github-runner-workdir/

# 检查 runner 进程状态
echo ""
echo -e "${BLUE}🏃 Runner 进程状态:${NC}"
kubectl exec -n github-runners "$CURRENT_POD" -- pgrep -f "Runner.Listener" && echo "✅ Runner.Listener 进程运行中" || echo "❌ Runner.Listener 进程未运行"

# 检查 runner 配置
echo ""
echo -e "${BLUE}⚙️ Runner 配置:${NC}"
kubectl exec -n github-runners "$CURRENT_POD" -- env | grep -E "(RUNNER_|GITHUB_)" | head -5

echo ""
echo -e "${GREEN}✅ 验证完成${NC}"
echo ""
echo -e "${YELLOW}💡 提示:${NC}"
echo "- 工作目录数据持久化在 PVC 中"
echo "- 重启后 Pod 会重新绑定同一个 PVC"
echo "- Runner 会自动重新注册到 GitHub"
echo "- 历史构建记录和缓存会被保留"