#!/bin/bash

# 清理和设置GitHub Token
# 用法: ./clean-token.sh "NEW_TOKEN_HERE"

set -e

if [ $# -eq 0 ]; then
    echo "❌ 错误：请提供新的GitHub Token"
    echo "使用方法: $0 \"NEW_TOKEN_HERE\""
    echo ""
    echo "获取新Token："
    echo "1. 访问 https://github.com/gszw90/k8s-app/settings/actions/runners"
    echo "2. 点击 'New self-hosted runner'"
    echo "3. 复制Token（确保没有换行符）"
    exit 1
fi

# 清理Token（移除换行符和空格）
NEW_TOKEN=$(echo "$1" | tr -d '\n\r' | xargs)

echo "🔧 清理并设置GitHub Token..."
echo "原始Token长度: ${#1}"
echo "清理后Token长度: ${#NEW_TOKEN}"
echo "Token（脱敏显示）: ${NEW_TOKEN:0:8}...${NEW_TOKEN: -8}"

# 验证Token格式
if [ ${#NEW_TOKEN} -lt 20 ]; then
    echo "⚠️  警告：Token长度似乎太短，请确认Token正确"
    echo "继续执行？(y/N)"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "❌ 操作已取消"
        exit 1
    fi
fi

# 编码Token
ENCODED_TOKEN=$(echo -n "$NEW_TOKEN" | base64 -w 0)

echo "📝 更新K8s Secret..."

# 备份当前配置
kubectl get secret github-runner-secret -n github-runners -o yaml > "secret-backup-$(date +%Y%m%d-%H%M%S).yaml"

# 更新Secret
kubectl patch secret github-runner-secret \
  -n github-runners \
  --type=merge \
  --patch="{
    \"data\": {
      \"RUNNER_TOKEN\": \"$ENCODED_TOKEN\"
    }
  }"

if [ $? -eq 0 ]; then
    echo "✅ Token更新成功"

    # 验证更新
    VERIFY_TOKEN=$(kubectl get secret github-runner-secret -n github-runners -o jsonpath='{.data.RUNNER_TOKEN}' | base64 -d)

    if [ "$VERIFY_TOKEN" = "$NEW_TOKEN" ]; then
        echo "✅ Token验证成功"
        echo ""
        echo "📋 下一步操作："
        echo "1. 重启Runner Pod: kubectl delete pod -n github-runners -l app=github-runner"
        echo "2. 等待新Pod启动并检查状态"
        echo "3. 在GitHub中验证Runner状态"
    else
        echo "❌ Token验证失败"
        exit 1
    fi
else
    echo "❌ Token更新失败"
    exit 1
fi

echo ""
echo "🎉 Token设置完成！"