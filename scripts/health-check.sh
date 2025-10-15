#!/bin/bash

# 健康检查脚本
# 使用方法: ./scripts/health-check.sh [service] [environment] [--detailed]

set -e

# 获取参数
SERVICE="$1"
ENVIRONMENT="$2"
DETAILED="$3"

# 验证参数
if [[ -z "$SERVICE" || -z "$ENVIRONMENT" ]]; then
    echo "❌ 错误: 缺少必需参数"
    echo "用法: $0 <service> <environment> [--detailed]"
    echo "示例: $0 first-app develop --detailed"
    exit 1
fi

echo "🧪 执行健康检查: $SERVICE ($ENVIRONMENT 环境)"
echo "================================================"

# 配置
NAMESPACE="app"
DEPLOYMENT_NAME="app-${SERVICE}-${ENVIRONMENT}"
HEALTH_TIMEOUT=30
MAX_RETRIES=5

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查函数
check_pod_status() {
    echo -e "${BLUE}📊 检查 Pod 状态...${NC}"

    local pod_status=$(kubectl get pods --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT" --no-headers)

    if [[ -z "$pod_status" ]]; then
        echo -e "${RED}❌ 未找到对应的 Pod${NC}"
        return 1
    fi

    echo "$pod_status" | while read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local ready=$(echo "$line" | awk '{print $2}')
        local status=$(echo "$line" | awk '{print $3}')
        local restarts=$(echo "$line" | awk '{print $4}')

        if [[ "$status" == "Running" && "$ready" == "1/1" ]]; then
            echo -e "  ${GREEN}✅ $pod_name: $ready $status (重启: $restarts)${NC}"
        else
            echo -e "  ${RED}❌ $pod_name: $ready $status (重启: $restarts)${NC}"
            return 1
        fi
    done
}

# 检查服务状态
check_service_status() {
    echo -e "${BLUE}🔍 检查服务状态...${NC}"

    local service_status=$(kubectl get service --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT" --no-headers)

    if [[ -z "$service_status" ]]; then
        echo -e "${RED}❌ 未找到对应的服务${NC}"
        return 1
    fi

    echo "$service_status" | while read -r line; do
        local service_name=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $2}')
        local cluster_ip=$(echo "$line" | awk '{print $3}')
        local ports=$(echo "$line" | awk '{print $5}')

        echo -e "  ${GREEN}✅ $service_name: $type ($cluster_ip) -> $ports${NC}"
    done
}

# 检查部署状态
check_deployment_status() {
    echo -e "${BLUE}🚀 检查部署状态...${NC}"

    local deployment_status=$(kubectl get deployment --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT" --no-headers)

    if [[ -z "$deployment_status" ]]; then
        echo -e "${RED}❌ 未找到对应的部署${NC}"
        return 1
    fi

    echo "$deployment_status" | while read -r line; do
        local deployment_name=$(echo "$line" | awk '{print $1}')
        local ready=$(echo "$line" | awk '{print $2}')
        local up_to_date=$(echo "$line" | awk '{print $3}')
        local available=$(echo "$line" | awk '{print $4}')

        if [[ "$ready" == "$up_to_date" && "$ready" == "$available" ]]; then
            echo -e "  ${GREEN}✅ $deployment_name: $ready ready, $up_to_date up-to-date, $available available${NC}"
        else
            echo -e "  ${YELLOW}⚠️ $deployment_name: $ready ready, $up_to_date up-to-date, $available available${NC}"
        fi
    done
}

# 检查 HTTP 端点
check_http_endpoint() {
    echo -e "${BLUE}🌐 检查 HTTP 端点...${NC}"

    local base_url="http://localhost"
    local endpoint_url

    # 根据服务类型确定端点
    if [[ "$SERVICE" == *"app" ]]; then
        endpoint_url="${base_url}/${SERVICE%%-app}"
    else
        endpoint_url="${base_url}"
    fi

    # 检查不同的路径
    local health_paths=()

    if [[ "$SERVICE" == *"app" ]]; then
        health_paths=("/ping" "/health" "/")
    else
        health_paths=("/health" "/")
    fi

    local success_count=0
    local total_count=${#health_paths[@]}

    for path in "${health_paths[@]}"; do
        local full_url="${endpoint_url}${path}"
        echo -n "  测试 $full_url ... "

        for i in $(seq 1 $MAX_RETRIES); do
            if curl -f -s --max-time 10 "$full_url" > /dev/null 2>&1; then
                echo -e "${GREEN}✅ 成功${NC}"
                ((success_count++))

                # 如果需要详细输出，显示响应内容
                if [[ "$DETAILED" == "--detailed" ]]; then
                    echo "    响应:"
                    curl -s --max-time 10 "$full_url" | head -5 | sed 's/^/      /'
                fi
                break
            else
                if [[ $i -eq $MAX_RETRIES ]]; then
                    echo -e "${RED}❌ 失败${NC}"
                else
                    echo -n "重试 $i/$MAX_RETRIES ... "
                    sleep 2
                fi
            fi
        done
    done

    if [[ $success_count -eq $total_count ]]; then
        return 0
    else
        echo -e "${YELLOW}⚠️ 成功率: $success_count/$total_count${NC}"
        return 1
    fi
}

# 检查 Pod 日志
check_pod_logs() {
    if [[ "$DETAILED" != "--detailed" ]]; then
        return 0
    fi

    echo -e "${BLUE}📋 检查最近的 Pod 日志...${NC}"

    local pod_name=$(kubectl get pods --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT" --no-headers | awk 'NR==1{print $1}')

    if [[ -n "$pod_name" ]]; then
        echo "  最近 20 行日志:"
        kubectl logs --namespace="$NAMESPACE" "$pod_name" --tail=20 | sed 's/^/    /'
    fi
}

# 检查资源使用情况
check_resource_usage() {
    if [[ "$DETAILED" != "--detailed" ]]; then
        return 0
    fi

    echo -e "${BLUE}📈 检查资源使用情况...${NC}"

    echo "  Pod 资源使用:"
    kubectl top pods --namespace="$NAMESPACE" -l app="$SERVICE" -l environment="$ENVIRONMENT" 2>/dev/null | sed 's/^/    /' || echo "    ⚠️ 无法获取资源使用信息"
}

# 生成健康检查报告
generate_report() {
    echo ""
    echo -e "${BLUE}📋 健康检查报告${NC}"
    echo "================================================"

    local overall_status="✅ 健康"

    # 检查关键指标
    local pod_ok=$(check_pod_status >/dev/null 2>&1 && echo "true" || echo "false")
    local http_ok=$(check_http_endpoint >/dev/null 2>&1 && echo "true" || echo "false")

    if [[ "$pod_ok" != "true" || "$http_ok" != "true" ]]; then
        overall_status="❌ 不健康"
    fi

    echo -e "总体状态: $overall_status"
    echo "服务: $SERVICE"
    echo "环境: $ENVIRONMENT"
    echo "命名空间: $NAMESPACE"
    echo "检查时间: $(date)"

    if [[ "$overall_status" != "✅ 健康" ]]; then
        echo ""
        echo -e "${YELLOW}🔧 建议的修复步骤:${NC}"
        echo "1. 检查 Pod 日志: kubectl logs -n $NAMESPACE deployment/$DEPLOYMENT_NAME"
        echo "2. 检查部署状态: kubectl describe deployment -n $NAMESPACE $DEPLOYMENT_NAME"
        echo "3. 重启部署: kubectl rollout restart deployment -n $NAMESPACE $DEPLOYMENT_NAME"
        echo "4. 检查事件: kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp"
    fi
}

# 主执行流程
main() {
    # 执行各项检查
    check_pod_status
    echo ""

    check_service_status
    echo ""

    check_deployment_status
    echo ""

    check_http_endpoint
    echo ""

    check_pod_logs
    echo ""

    check_resource_usage
    echo ""

    generate_report
}

# 错误处理
trap 'echo -e "${RED}❌ 健康检查脚本执行出错${NC}"; exit 1' ERR

# 执行主函数
main "$@"