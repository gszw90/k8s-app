#!/bin/bash

# K8s 部署状态查看脚本
# 用法: ./deploy-status.sh [environment]
# 示例: ./deploy-status.sh develop
#      ./deploy-status.sh

set -e

# 参数处理
ENVIRONMENT="$1"

# 如果指定了环境，只显示该环境的信息
if [ -n "$ENVIRONMENT" ]; then
    if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|prod)$ ]]; then
        echo "❌ 无效的环境名称: $ENVIRONMENT"
        echo "支持的环境: develop, staging, prod"
        exit 1
    fi

    NAMESPACE="app-${ENVIRONMENT}"

    echo "📊 部署状态报告 - $ENVIRONMENT 环境"
    echo "==================================="
    echo "🏷️ Namespace: $NAMESPACE"
    echo ""

    # 检查 namespace 是否存在
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo "❌ Namespace 不存在: $NAMESPACE"
        exit 1
    fi

    # 显示所有 deployments
    echo "🚀 Deployments:"
    kubectl get deployments -n "$NAMESPACE" -o wide

    echo ""
    echo "🏷️ Pods 状态:"
    kubectl get pods -n "$NAMESPACE" -o wide

    echo ""
    echo "🔌 Services 状态:"
    kubectl get services -n "$NAMESPACE" -o wide

    echo ""
    echo "📈 最近事件:"
    kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -10

else
    # 显示所有环境的信息
    echo "📊 部署状态报告 - 所有环境"
    echo "============================"

    for env in develop staging prod; do
        NAMESPACE="app-${env}"

        echo ""
        echo "🌍 $env 环境 (Namespace: $NAMESPACE)"
        echo "------------------------------------"

        if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
            # 简要显示该环境的部署状态
            echo "Deployments:"
            kubectl get deployments -n "$NAMESPACE" --no-headers | awk '{printf "  %-25s %-10s %-10s %-10s\n", $1, $2, $3, $4}' || echo "  无 deployments"

            echo ""
            echo "Pods 状态:"
            kubectl get pods -n "$NAMESPACE" --no-headers | awk '{printf "  %-35s %-10s %-10s %s\n", $1, $2, $3, $4}' || echo "  无 pods"
        else
            echo "  ❌ Namespace 不存在"
        fi
    done

    echo ""
    echo "🔧 详细查看命令:"
    echo "  ./scripts/deploy-status.sh develop"
    echo "  ./scripts/deploy-status.sh staging"
    echo "  ./scripts/deploy-status.sh prod"
fi

echo ""
echo "🔄 回滚命令:"
echo "  ./scripts/rollback.sh <app-name> <environment> [revision]"
echo ""
echo "🌐 端口转发命令:"
echo "  kubectl port-forward -n app-develop service/backend-first-app-service 8080:80"
echo "  kubectl port-forward -n app-staging service/frontend-first-app-service 8081:80"