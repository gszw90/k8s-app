#!/bin/bash

# K8s 应用回滚脚本
# 用法: ./rollback.sh <app-name> <environment> [revision]
# 示例: ./rollback.sh backend-first-app develop 2
#      ./rollback.sh frontend-first-app staging

set -e

# 参数检查
if [ $# -lt 2 ]; then
    echo "❌ 参数不足"
    echo "用法: $0 <app-name> <environment> [revision]"
    echo "示例: $0 backend-first-app develop 2"
    echo "      $0 frontend-first-app staging"
    echo ""
    echo "参数说明:"
    echo "  app-name    应用名称 (格式: domain-app-name, 如: backend-first-app)"
    echo "  environment 环境名称 (develop, staging, prod)"
    echo "  revision    可选，回滚到的版本号。不指定则回滚到上一个版本"
    exit 1
fi

APP_NAME="$1"
ENVIRONMENT="$2"
REVISION="$3"

# 验证环境参数
if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|prod)$ ]]; then
    echo "❌ 无效的环境名称: $ENVIRONMENT"
    echo "支持的环境: develop, staging, prod"
    exit 1
fi

# Namespace 映射
NAMESPACE="app-${ENVIRONMENT}"

echo "🔄 开始回滚操作"
echo "=================="
echo "📦 应用: $APP_NAME"
echo "🌍 环境: $ENVIRONMENT"
echo "🏷️ Namespace: $NAMESPACE"

# 验证 K8s 集群连接
echo "🔍 验证集群连接..."
if ! kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
    echo "❌ 无法连接到 Kubernetes 集群"
    echo "请检查 kubeconfig 配置"
    exit 1
fi
echo "✅ 集群连接正常"

# 检查 namespace 是否存在
echo "🏷️ 检查 namespace..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace 不存在: $NAMESPACE"
    echo "可用的 namespaces:"
    kubectl get namespaces
    exit 1
fi
echo "✅ Namespace 存在: $NAMESPACE"

# 检查 deployment 是否存在
echo "🚀 检查 deployment..."
if ! kubectl get deployment "$APP_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment 不存在: $APP_NAME"
    echo "Namespace '$NAMESPACE' 中的 deployments:"
    kubectl get deployments -n "$NAMESPACE"
    exit 1
fi
echo "✅ Deployment 存在: $APP_NAME"

# 获取部署历史
echo "📋 获取部署历史..."
echo "当前部署历史:"
kubectl rollout history deployment/"$APP_NAME" -n "$NAMESPACE"

# 如果没有指定 revision，获取上一个版本
if [ -z "$REVISION" ]; then
    echo ""
    echo "🔍 未指定版本号，获取可回滚的版本..."

    # 获取当前的 revision
    CURRENT_REVISION=$(kubectl rollout history deployment/"$APP_NAME" -n "$NAMESPACE" | grep "revision" | tail -1 | awk '{print $1}' | cut -d':' -f2)

    if [ -z "$CURRENT_REVISION" ]; then
        echo "❌ 无法获取当前版本信息"
        exit 1
    fi

    echo "当前版本: $CURRENT_REVISION"

    # 计算上一个版本
    if [ "$CURRENT_REVISION" -gt 1 ]; then
        REVISION=$((CURRENT_REVISION - 1))
        echo "将回滚到版本: $REVISION"
    else
        echo "❌ 当前已是第一个版本，无法回滚"
        exit 1
    fi
else
    echo "指定回滚版本: $REVISION"
fi

# 验证 revision 是否存在
echo "🔍 验证版本 $REVISION 是否存在..."
if ! kubectl rollout history deployment/"$APP_NAME" -n "$NAMESPACE" --revision="$REVISION" >/dev/null 2>&1; then
    echo "❌ 版本 $REVISION 不存在"
    echo "可用版本:"
    kubectl rollout history deployment/"$APP_NAME" -n "$NAMESPACE" | grep "revision"
    exit 1
fi
echo "✅ 版本 $REVISION 存在"

# 显示当前状态
echo ""
echo "📊 回滚前状态:"
echo "================"
kubectl get pods -n "$NAMESPACE" -l "app=$APP_NAME" -l "environment=$ENVIRONMENT"

# 确认回滚操作
echo ""
read -p "⚠️  确认要回滚 $APP_NAME 到版本 $REVISION 吗？(y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 回滚操作已取消"
    exit 0
fi

# 执行回滚
echo ""
echo "🔄 执行回滚操作..."
echo "kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE --to-revision=$REVISION"

if kubectl rollout undo deployment/"$APP_NAME" -n "$NAMESPACE" --to-revision="$REVISION"; then
    echo "✅ 回滚命令执行成功"
else
    echo "❌ 回滚命令执行失败"
    exit 1
fi

# 等待回滚完成
echo ""
echo "⏳ 等待回滚完成..."
echo "kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s"

if kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
    echo "✅ 回滚完成"
else
    echo "❌ 回滚超时或失败"
    echo "请检查 pod 状态和日志"
    exit 1
fi

# 显示回滚后状态
echo ""
echo "📊 回滚后状态:"
echo "================"
kubectl get pods -n "$NAMESPACE" -l "app=$APP_NAME" -l "environment=$ENVIRONMENT"

echo ""
echo "📋 最新的部署历史:"
kubectl rollout history deployment/"$APP_NAME" -n "$NAMESPACE" | tail -5

# 提供有用的命令
echo ""
echo "🔧 有用的命令:"
echo "=============="
echo "查看 pod 状态: kubectl get pods -n $NAMESPACE -l app=$APP_NAME"
echo "查看 pod 日志: kubectl logs -n $NAMESPACE -l app=$APP_NAME --tail=50"
echo "查看部署历史: kubectl rollout history deployment/$APP_NAME -n $NAMESPACE"
echo "查看事件: kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp"

echo ""
echo "🎉 回滚操作完成！"
echo "应用 $APP_NAME 已成功回滚到版本 $REVISION"