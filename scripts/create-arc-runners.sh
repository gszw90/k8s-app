#!/bin/bash

# 创建ARC Runner资源脚本
# 为不同环境创建RunnerDeployment和HorizontalRunnerAutoscaler

set -e

echo "🏃 创建ARC Runner资源"
echo "==================="

# 配置变量
REPOSITORY="gszw90/k8s-app"
ARC_NAMESPACE="actions-runner-system"
DEFAULT_ENVIRONMENTS=("develop" "staging" "prod")

# 显示帮助信息
show_help() {
    echo "用法: $0 [环境1] [环境2] ..."
    echo ""
    echo "示例:"
    echo "  $0                    # 创建所有环境的runner"
    echo "  $0 develop           # 只创建开发环境runner"
    echo "  $0 develop staging   # 创建开发和预发布环境runner"
    echo ""
    echo "支持的环境: ${DEFAULT_ENVIRONMENTS[*]}"
}

# 检查依赖
check_dependencies() {
    echo "🔍 检查依赖..."

    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl未安装"
        exit 1
    fi

    # 检查ARC是否已部署
    if ! kubectl get crd runnerdeployments.actions.summerwind.dev &> /dev/null; then
        echo "❌ Actions Runner Controller未部署"
        echo "💡 请先运行: ./scripts/deploy-arc-controller.sh"
        exit 1
    fi

    echo "✅ 依赖检查通过"
}

# 创建命名空间
create_namespace() {
    local namespace="github-runners-$1"

    echo "🏷️ 创建命名空间: $namespace"

    if kubectl get namespace "$namespace" &> /dev/null; then
        echo "✅ 命名空间 $namespace 已存在"
    else
        kubectl create namespace "$namespace"
        echo "✅ 命名空间 $namespace 创建成功"
    fi
}

# 创建RunnerDeployment
create_runner_deployment() {
    local env=$1
    local namespace="github-runners-$env"
    local min_replicas
    local max_replicas

    # 根据环境设置不同的副本数
    case "$env" in
        "develop")
            min_replicas=0
            max_replicas=3
            ;;
        "staging")
            min_replicas=0
            max_replicas=2
            ;;
        "prod")
            min_replicas=1
            max_replicas=5
            ;;
        *)
            min_replicas=0
            max_replicas=2
            ;;
    esac

    echo "🚀 创建RunnerDeployment: $env (min: $min_replicas, max: $max_replicas)"

    cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: ${env}-runner
  namespace: ${namespace}
  labels:
    app: github-runner
    environment: ${env}
spec:
  replicas: ${min_replicas}
  template:
    spec:
      repository: ${REPOSITORY}
      labels:
        app: github-runner
        environment: ${env}
      # 挂载Docker socket (如果需要)
      # dockerdWithinRunnerContainer: true
      # env:
      #   - name: DOCKER_TLS_CERTDIR
      #     value: ""
EOF

    echo "✅ RunnerDeployment $env 创建成功"
}

# 创建HorizontalRunnerAutoscaler
create_runner_autoscaler() {
    local env=$1
    local namespace="github-runners-$env"
    local max_replicas

    # 根据环境设置最大副本数
    case "$env" in
        "develop")
            max_replicas=3
            ;;
        "staging")
            max_replicas=2
            ;;
        "prod")
            max_replicas=5
            ;;
        *)
            max_replicas=2
            ;;
    esac

    echo "📈 创建HorizontalRunnerAutoscaler: $env (max: $max_replicas)"

    cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: ${env}-hra
  namespace: ${namespace}
  labels:
    app: github-runner
    environment: ${env}
spec:
  scaleTargetRef:
    name: ${env}-runner
  minReplicas: 0
  maxReplicas: ${max_replicas}
  scaleUpTriggers:
  - githubEvent:
      workflowJob: {}
    duration: "30m"
  # 可选：基于队列深度的扩展
  # scaleUpTriggers:
  # - amount: 1
  #   duration: "10m"
  #   expression: |
  #     'runner_job_queued' > 0
EOF

    echo "✅ HorizontalRunnerAutoscaler $env 创建成功"
}

# 创建RBAC权限
create_rbac() {
    local env=$1
    local namespace="github-runners-$env"

    echo "🔐 创建RBAC权限: $env"

    # ServiceAccount
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner-${env}
  namespace: ${namespace}
  labels:
    app: github-runner
    environment: ${env}
EOF

    # Role (权限可以根据需要调整)
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-runner-${env}-role
  namespace: app-${env}
  labels:
    app: github-runner
    environment: ${env}
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "events"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

    # RoleBinding
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-runner-${env}-binding
  namespace: app-${env}
  labels:
    app: github-runner
    environment: ${env}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-runner-${env}-role
subjects:
- kind: ServiceAccount
  name: github-runner-${env}
  namespace: ${namespace}
EOF

    echo "✅ RBAC权限 $env 创建成功"
}

# 创建GitHub App认证secret (在每个命名空间)
create_github_app_secret() {
    local env=$1
    local namespace="github-runners-$env"

    echo "🔑 创建GitHub App认证secret: $env"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: github-app-credentials
  namespace: ${namespace}
type: Opaque
data:
  github_app_id: $(echo -n "2168366" | base64)
  github_app_installation_id: $(echo -n "91349326" | base64)
  github_app_private_key: $(cat ./github-app-private-key.pem | base64 -w 0)
EOF

    echo "✅ GitHub App认证secret $env 创建成功"
}

# 更新RunnerDeployment使用GitHub App认证
update_runner_deployment_with_auth() {
    local env=$1
    local namespace="github-runners-$env"

    echo "🔄 更新RunnerDeployment使用GitHub App认证: $env"

    cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: ${env}-runner
  namespace: ${namespace}
  labels:
    app: github-runner
    environment: ${env}
spec:
  replicas: 0
  template:
    spec:
      repository: ${REPOSITORY}
      githubAPICredentialsFrom:
        secretRef:
          name: github-app-credentials
      serviceAccountName: github-runner-${env}
      labels:
        app: github-runner
        environment: ${env}
EOF

    echo "✅ RunnerDeployment $env 更新成功"
}

# 验证资源创建
verify_resources() {
    local env=$1
    local namespace="github-runners-$env"

    echo "🔍 验证资源创建: $env"

    echo "📋 RunnerDeployments:"
    kubectl get runnerdeployments -n "$namespace" || echo "⚠️  RunnerDeployment未找到"

    echo "📋 HorizontalRunnerAutoscalers:"
    kubectl get horizontalrunnerautoscalers -n "$namespace" || echo "⚠️  HRA未找到"

    echo "📋 Runners:"
    kubectl get runners -n "$namespace" || echo "ℹ️  暂无活跃runner"

    echo "✅ 资源验证完成: $env"
}

# 显示GitHub Actions配置示例
show_github_actions_config() {
    echo ""
    echo "📝 GitHub Actions配置示例"
    echo "========================="
    echo ""
    echo "更新您的 .github/workflows/deploy-backend.yaml 文件："
    echo ""
    cat <<'EOF'
jobs:
  build-and-deploy:
    runs-on: [self-hosted, linux, develop]  # 指定环境和标签
    if: github.ref == 'refs/heads/develop-backend-first-app'

    steps:
    - uses: actions/checkout@v4

    - name: Setup Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.24'

    - name: Build application
      run: |
        cd backend
        go build -o first_app app/first_app/main.go

    - name: Build and push Docker image
      run: |
        # 您的构建脚本

    - name: Deploy to Kubernetes
      run: |
        # 使用ServiceAccount认证的部署脚本
        ./scripts/deploy-with-serviceaccount.sh app-develop first-app backend develop
EOF
    echo ""
    echo "🏷️ Runner标签对应关系："
    echo "- develop环境: [self-hosted, linux, develop]"
    echo "- staging环境: [self-hosted, linux, staging]"
    echo "- prod环境: [self-hosted, linux, prod]"
}

# 显示监控命令
show_monitoring_commands() {
    echo ""
    echo "🔍 有用的监控命令"
    echo "=================="
    echo ""
    echo "查看所有runner:"
    echo "kubectl get runners -A"
    echo ""
    echo "查看runner部署:"
    echo "kubectl get runnerdeployments -A"
    echo ""
    echo "查看自动扩展器:"
    echo "kubectl get horizontalrunnerautoscalers -A"
    echo ""
    echo "查看特定环境的runner:"
    echo "kubectl get runners -n github-runners-develop"
    echo ""
    echo "查看runner日志:"
    echo "kubectl logs -f <runner-pod-name> -n github-runners-develop"
    echo ""
    echo "查看ARC Controller日志:"
    echo "kubectl logs -f deployment/controller-manager -n actions-runner-system"
}

# 主函数
main() {
    # 解析命令行参数
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    # 确定要创建的环境
    local environments=()
    if [[ $# -eq 0 ]]; then
        environments=("${DEFAULT_ENVIRONMENTS[@]}")
    else
        for arg in "$@"; do
            if [[ " ${DEFAULT_ENVIRONMENTS[*]} " =~ " $arg " ]]; then
                environments+=("$arg")
            else
                echo "⚠️  不支持的环境: $arg"
                echo "支持的环境: ${DEFAULT_ENVIRONMENTS[*]}"
                exit 1
            fi
        done
    fi

    echo "将为以下环境创建runner资源: ${environments[*]}"
    echo ""

    # 检查依赖
    check_dependencies

    # 为每个环境创建资源
    for env in "${environments[@]}"; do
        echo ""
        echo "🏃 处理环境: $env"
        echo "=================="

        create_namespace "$env"
        create_github_app_secret "$env"
        create_rbac "$env"
        create_runner_deployment "$env"
        update_runner_deployment_with_auth "$env"
        create_runner_autoscaler "$env"
        verify_resources "$env"

        echo "✅ 环境 $env 配置完成"
    done

    # 显示配置示例和监控命令
    show_github_actions_config
    show_monitoring_commands

    echo ""
    echo "🎉 所有Runner资源创建完成！"
    echo ""
    echo "💡 下一步："
    echo "1. 更新GitHub Actions workflow文件"
    echo "2. 提交代码触发CI/CD测试"
    echo "3. 监控runner自动扩展情况"
}

# 执行主函数
main "$@"