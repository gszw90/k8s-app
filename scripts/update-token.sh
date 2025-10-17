#!/bin/bash

# 更新GitHub Runner Token脚本
# 使用方法: ./update-token.sh YOUR_NEW_TOKEN_HERE

set -e

if [ $# -eq 0 ]; then
    echo "❌ 错误：请提供新的GitHub Token"
    echo "使用方法: $0 YOUR_NEW_TOKEN_HERE"
    echo ""
    echo "获取Token步骤："
    echo "1. 访问 https://github.com/gszw90/k8s-app/settings/actions/runners"
    echo "2. 点击 'New self-hosted runner'"
    echo "3. 选择 Linux 和 x64"
    echo "4. 复制 Configure 部分的 Token"
    exit 1
fi

NEW_TOKEN="$1"
NAMESPACE="github-runners"
SECRET_NAME="github-runner-secret"

echo "🔧 更新GitHub Runner Token..."
echo "================================="

# 验证Token格式（应该是64个字符的base64字符串）
if [ ${#NEW_TOKEN} -ne 64 ]; then
    echo "⚠️  警告：Token长度不是64个字符，请确认Token正确"
    echo "当前Token长度: ${#NEW_TOKEN}"
    echo "继续执行？(y/N)"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "❌ 操作已取消"
        exit 1
    fi
fi

# 显示当前Token（脱敏）
echo "🔑 当前Token（脱敏显示）: ${NEW_TOKEN:0:8}...${NEW_TOKEN: -8}"

# 编码Token为base64
ENCODED_TOKEN=$(echo -n "$NEW_TOKEN" | base64)

echo "📝 更新Secret: $SECRET_NAME"
echo "命名空间: $NAMESPACE"

# 备份当前Secret
echo "💾 备份当前Secret..."
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml > "github-runner-secret-backup-$(date +%Y%m%d-%H%M%S).yaml"
echo "✅ 备份完成"

# 更新Secret
echo "🔄 更新Secret中的RUNNER_TOKEN..."
kubectl patch secret "$SECRET_NAME" \
  -n "$NAMESPACE" \
  --patch="{
    \"data\": {
      \"RUNNER_TOKEN\": \"$ENCODED_TOKEN\"
    }
  }"

if [ $? -eq 0 ]; then
    echo "✅ Secret更新成功"

    # 验证更新
    echo "🔍 验证更新结果..."
    UPDATED_TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.RUNNER_TOKEN}' | base64 -d)

    if [ "$UPDATED_TOKEN" = "$NEW_TOKEN" ]; then
        echo "✅ Token验证成功"
        echo ""
        echo "📋 下一步操作："
        echo "1. 执行部署脚本: ./deploy-fixed-runner.sh"
        echo "2. 或者手动执行: kubectl apply -f github-runner-fixed.yaml -n github-runners"
        echo ""
        echo "🎯 预期结果："
        echo "- 新的Pod将使用新Token注册到GitHub"
        echo "- Runner状态在GitHub中显示为 'Idle'"
        echo "- GitHub Actions工作流程可以正常执行"
    else
        echo "❌ Token验证失败"
        echo "期望: $NEW_TOKEN"
        echo "实际: $UPDATED_TOKEN"
        exit 1
    fi
else
    echo "❌ Secret更新失败"
    echo "请检查："
    echo "1. kubectl是否正常工作"
    echo "2. 是否有权限修改命名空间 $NAMESPACE 中的Secret"
    echo "3. Secret名称是否正确: $SECRET_NAME"
    exit 1
fi

echo ""
echo "🎉 Token更新完成！"