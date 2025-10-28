#!/bin/bash

# kubectl缓存状态检查脚本
# 检查共享卷、缓存管理器和kubectl状态

set -e

# 配置变量
NAMESPACE="github-runners"
DEPLOYMENT_NAME="kubectl-cache-manager"
PVC_NAME="kubectl-cache-pvc"
PV_NAME="kubectl-cache-pv"

# 颜色输出函数
print_success() {
    echo -e "✅ $1"
}

print_error() {
    echo -e "❌ $1"
}

print_info() {
    echo -e "ℹ️  $1"
}

print_warning() {
    echo -e "⚠️  $1"
}

print_header() {
    echo -e "\n🔍 $1"
    echo "=================================================="
}

# 检查存储状态
check_storage_status() {
    print_header "存储状态检查"

    # 检查PersistentVolume
    local pv_status=$(kubectl get pv $PV_NAME -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    print_info "PersistentVolume ($PV_NAME): $pv_status"

    if [[ "$pv_status" == "Available" || "$pv_status" == "Bound" ]]; then
        local pv_capacity=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.capacity.storage}' 2>/dev/null || echo "Unknown")
        local pv_access=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo "Unknown")
        print_info "  容量: $pv_capacity, 访问模式: $pv_access"
    fi

    # 检查PersistentVolumeClaim
    local pvc_status=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    print_info "PersistentVolumeClaim ($PVC_NAME): $pvc_status"

    if [[ "$pvc_status" == "Bound" ]]; then
        local pvc_capacity=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "Unknown")
        local bound_pv=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "Unknown")
        print_info "  容量: $pvc_capacity, 绑定PV: $bound_pv"
    fi

    # 检查存储类
    local storage_class=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "Unknown")
    print_info "存储类: $storage_class"
}

# 检查缓存管理器状态
check_cache_manager_status() {
    print_header "缓存管理器状态检查"

    # 检查Deployment状态
    local deployment_status=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}/{$.spec.replicas}' 2>/dev/null || echo "NotFound")
    print_info "Deployment状态: $deployment_status"

    # 检查Pod状态
    local pod_name=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$pod_name" ]]; then
        local pod_status=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local pod_ready=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        local pod_restart=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

        print_info "Pod状态: $pod_status"
        print_info "Pod就绪: $pod_ready"
        print_info "重启次数: $pod_restart"

        # 检查资源使用
        local pod_cpu=$(kubectl top pod $pod_name -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $2}' || echo "Unknown")
        local pod_memory=$(kubectl top pod $pod_name -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $3}' || echo "Unknown")
        print_info "资源使用: CPU=$pod_cpu, Memory=$pod_memory"
    else
        print_error "未找到缓存管理器Pod"
        return 1
    fi
}

# 检查kubectl状态
check_kubectl_status() {
    print_header "kubectl状态检查"

    local pod_name=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$pod_name" ]]; then
        print_error "缓存管理器Pod未就绪，无法检查kubectl"
        return 1
    fi

    # 检查kubectl文件是否存在
    local kubectl_exists=$(kubectl exec -n $NAMESPACE $pod_name -- test -f /shared/kubectl && echo "true" || echo "false")
    print_info "kubectl文件存在: $kubectl_exists"

    if [[ "$kubectl_exists" == "true" ]]; then
        # 检查文件大小
        local kubectl_size=$(kubectl exec -n $NAMESPACE $pod_name -- ls -la /shared/kubectl | awk '{print $5}' || echo "0")
        print_info "kubectl文件大小: $kubectl_size bytes"

        # 检查版本
        local kubectl_version=$(kubectl exec -n $NAMESPACE $pod_name -- /shared/kubectl version --client --short 2>/dev/null | head -1 || echo "Unknown")
        print_info "kubectl版本: $kubectl_version"

        # 检查功能性
        local kubectl_functional=$(kubectl exec -n $NAMESPACE $pod_name -- /shared/kubectl version --client >/dev/null 2>&1 && echo "正常" || echo "异常")
        if [[ "$kubectl_functional" == "正常" ]]; then
            print_success "kubectl功能验证: $kubectl_functional"
        else
            print_error "kubectl功能验证: $kubectl_functional"
        fi

        # 检查权限
        local kubectl_permissions=$(kubectl exec -n $NAMESPACE $pod_name -- ls -la /shared/kubectl | awk '{print $1}' || echo "Unknown")
        print_info "kubectl文件权限: $kubectl_permissions"
    else
        print_error "kubectl文件不存在"
    fi

    # 检查存储使用情况
    local shared_usage=$(kubectl exec -n $NAMESPACE $pod_name -- df -h /shared 2>/dev/null | tail -1 || echo "Unknown")
    local local_usage=$(kubectl exec -n $NAMESPACE $pod_name -- df -h /local 2>/dev/null | tail -1 || echo "Unknown")
    print_info "共享卷使用: $shared_usage"
    print_info "本地缓存使用: $local_usage"
}

# 检查配置信息
check_configuration() {
    print_header "配置信息检查"

    # 检查环境变量
    local kubectl_version=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KUBECTL_VERSION")].value}' 2>/dev/null || echo "NotSet")
    local update_strategy=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="UPDATE_STRATEGY")].value}' 2>/dev/null || echo "NotSet")

    print_info "配置的kubectl版本: $kubectl_version"
    print_info "更新策略: $update_strategy"

    # 检查健康检查配置
    local liveness_probe=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null || echo "NotConfigured")
    local readiness_probe=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null || echo "NotConfigured")

    print_info "存活探针: $(if [[ "$liveness_probe" != "NotConfigured" ]]; then echo "已配置"; else echo "未配置"; fi)"
    print_info "就绪探针: $(if [[ "$readiness_probe" != "NotConfigured" ]]; then echo "已配置"; else echo "未配置"; fi)"

    # 检查资源限制
    local cpu_request=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "NotSet")
    local memory_request=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "NotSet")
    local cpu_limit=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "NotSet")
    local memory_limit=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "NotSet")

    print_info "资源请求: CPU=$cpu_request, Memory=$memory_request"
    print_info "资源限制: CPU=$cpu_limit, Memory=$memory_limit"
}

# 检查最近事件
check_recent_events() {
    print_header "最近事件检查"

    local events=$(kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' --field-selector involvedObject.name=$DEPLOYMENT_NAME | tail -10)
    if [[ -n "$events" ]]; then
        echo "$events"
    else
        print_info "没有找到最近的事件"
    fi
}

# 生成健康报告
generate_health_report() {
    print_header "健康状态总结"

    # 计算健康分数
    local storage_score=0
    local manager_score=0
    local kubectl_score=0

    # 存储健康检查
    local pvc_status=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$pvc_status" == "Bound" ]]; then
        storage_score=100
    elif [[ "$pvc_status" == "Pending" ]]; then
        storage_score=50
    else
        storage_score=0
    fi

    # 缓存管理器健康检查
    local pod_ready=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [[ "$pod_ready" == "True" ]]; then
        manager_score=100
    elif [[ "$pod_ready" == "False" ]]; then
        manager_score=0
    else
        manager_score=50
    fi

    # kubectl健康检查
    local kubectl_exists=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT_NAME -- test -f /shared/kubectl && echo "true" || echo "false" 2>/dev/null || echo "false")
    if [[ "$kubectl_exists" == "true" ]]; then
        local kubectl_functional=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT_NAME -- /shared/kubectl version --client >/dev/null 2>&1 && echo "true" || echo "false" 2>/dev/null || echo "false")
        if [[ "$kubectl_functional" == "true" ]]; then
            kubectl_score=100
        else
            kubectl_score=50
        fi
    else
        kubectl_score=0
    fi

    # 计算总分
    local total_score=$(( (storage_score + manager_score + kubectl_score) / 3 ))

    echo "🏥 健康评分:"
    echo "  存储状态: $storage_score/100"
    echo "  管理器状态: $manager_score/100"
    echo "  kubectl状态: $kubectl_score/100"
    echo "  综合评分: $total_score/100"

    # 健康状态判断
    if [[ $total_score -ge 80 ]]; then
        print_success "系统健康状态: 优秀"
    elif [[ $total_score -ge 60 ]]; then
        print_warning "系统健康状态: 良好"
    else
        print_error "系统健康状态: 需要关注"
    fi
}

# 显示帮助信息
show_help() {
    echo "kubectl缓存状态检查脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -s, --storage          仅检查存储状态"
    echo "  -m, --manager          仅检查缓存管理器状态"
    echo "  -k, --kubectl          仅检查kubectl状态"
    echo "  -c, --config           仅检查配置信息"
    echo "  -e, --events           仅检查最近事件"
    echo "  -r, --report           生成健康报告"
    echo "  -a, --all              检查所有状态（默认）"
    echo "  -h, --help             显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                    # 检查所有状态"
    echo "  $0 --report           # 生成健康报告"
    echo "  $0 --storage          # 仅检查存储"
    echo ""
}

# 主函数
main() {
    local check_storage="false"
    local check_manager="false"
    local check_kubectl="false"
    local check_config="false"
    local check_events="false"
    local generate_report="false"

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--storage)
                check_storage="true"
                shift
                ;;
            -m|--manager)
                check_manager="true"
                shift
                ;;
            -k|--kubectl)
                check_kubectl="true"
                shift
                ;;
            -c|--config)
                check_config="true"
                shift
                ;;
            -e|--events)
                check_events="true"
                shift
                ;;
            -r|--report)
                generate_report="true"
                shift
                ;;
            -a|--all)
                check_storage="true"
                check_manager="true"
                check_kubectl="true"
                check_config="true"
                check_events="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                print_error "无效参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 如果没有指定具体检查项，默认检查所有
    if [[ "$check_storage" == "false" && "$check_manager" == "false" && "$check_kubectl" == "false" && "$check_config" == "false" && "$check_events" == "false" && "$generate_report" == "false" ]]; then
        check_storage="true"
        check_manager="true"
        check_kubectl="true"
        check_config="true"
        check_events="false"
        generate_report="true"
    fi

    echo "🔍 kubectl缓存状态检查工具"
    echo "=========================="

    # 执行检查
    if [[ "$check_storage" == "true" ]]; then
        check_storage_status
    fi

    if [[ "$check_manager" == "true" ]]; then
        check_cache_manager_status
    fi

    if [[ "$check_kubectl" == "true" ]]; then
        check_kubectl_status
    fi

    if [[ "$check_config" == "true" ]]; then
        check_configuration
    fi

    if [[ "$check_events" == "true" ]]; then
        check_recent_events
    fi

    if [[ "$generate_report" == "true" ]]; then
        generate_health_report
    fi

    echo ""
    print_success "kubectl缓存状态检查完成！"
}

# 执行主函数
main "$@"