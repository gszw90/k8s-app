# 微服务CI/CD完整实践教程
## 基于 Kubernetes + GitHub Actions + Traefik 的自动化部署

---

## 📋 目录

1. [项目架构概述](#1-项目架构概述)
2. [环境准备](#2-环境准备)
3. [Docker 配置与最佳实践](#3-docker-配置与最佳实践)
4. [Kubernetes 配置详解](#4-kubernetes-配置详解)
5. [GitHub Actions CI/CD 流水线](#5-github-actions-cicd-流水线)
6. [分支命名规范与自动化解析](#6-分支命名规范与自动化解析)
7. [部署验证与监控](#7-部署验证与监控)
8. [问题排查与故障排除](#8-问题排查与故障排除)
9. [最佳实践总结](#9-最佳实践总结)
10. [扩展与优化](#10-扩展与优化)

---

## 1. 项目架构概述

### 1.1 微服务架构
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │   Backend-1     │    │   Backend-2     │
│   (Node.js)     │    │   (Go Gin)      │    │   (Go Gin)      │
│   Port: 3000    │    │   Port: 18080   │    │   Port: 18081   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Traefik Gateway│
                    │  (Ingress)      │
                    └─────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Kubernetes     │
                    │  Cluster        │
                    └─────────────────┘
```

### 1.2 目录结构
```
project/
├── backend/
│   ├── app/
│   │   ├── first_app/main.go      # 第一个后端服务
│   │   └── second_app/main.go     # 第二个后端服务
│   ├── go.mod                     # Go 模块依赖
│   └── go.sum
├── frontend/
│   └── first_app/
│       ├── package.json           # Node.js 配置
│       └── src/app.js            # 前端服务
├── docker/                       # Docker 配置文件
│   ├── first-app/
│   │   ├── Dockerfile.develop
│   │   ├── Dockerfile.staging
│   │   └── Dockerfile.prod
│   ├── second-app/
│   └── web-app/
├── k8s/                          # Kubernetes 配置
│   └── local-dev-apps.yaml
├── scripts/                      # 辅助脚本
│   └── parse-branch.sh
└── .github/workflows/            # CI/CD 配置
    └── deploy-monorepo.yaml
```

### 1.3 核心技术栈
- **后端**: Go 1.24 + Gin Web Framework
- **前端**: Node.js + Express
- **容器化**: Docker (多阶段构建)
- **编排**: Kubernetes (本地集群)
- **网关**: Traefik v2 (Ingress Controller)
- **CI/CD**: GitHub Actions + 自托管 Runner
- **镜像仓库**: 本地 Docker Registry

---

## 2. 环境准备

### 2.1 基础环境要求

#### 系统要求
- Linux (Ubuntu 20.04+ 推荐)
- Docker 20.10+
- Kubernetes 1.24+ (本地集群)
- Git 2.30+

#### 硬件要求
- CPU: 4核心以上
- 内存: 8GB 以上
- 存储: 50GB 可用空间

### 2.2 安装和配置

#### Docker 安装
```bash
# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 配置 Docker 用户组
sudo usermod -aG docker $USER

# 启动 Docker 服务
sudo systemctl start docker
sudo systemctl enable docker

# 验证安装
docker --version
docker info
```

#### Kubernetes 本地集群
```bash
# 使用 k3s 创建轻量级集群
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# 或者使用 kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# 创建集群
kind create cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

# 配置 kubectl
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config  # 对于 k3s
# 或
export KUBECONFIG="$(kind get kubeconfig-path --name="kind")"  # 对于 kind

# 验证集群
kubectl cluster-info
kubectl get nodes
```

#### Traefik 安装
```bash
# 安装 Traefik v2
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/content/static/traefik-v2.10/quick-start.yaml

# 或者使用 Helm
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm install traefik traefik/traefik --namespace traefik --create-namespace

# 验证安装
kubectl get pods -n traefik
kubectl get svc -n traefik
```

### 2.3 GitHub 自托管 Runner 配置

#### 创建 Runner
```bash
# 创建运行目录
mkdir /home/zeng/actions-runner
cd /home/zeng/actions-runner

# 下载 Runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# 配置 Runner (需要从 GitHub Settings 获取 token)
./config.sh --url https://github.com/zeng/wsl_first --token YOUR_TOKEN_HERE

# 安装并启动服务
sudo ./svc.sh install
sudo ./svc.sh start
```

#### Runner 权限配置
```bash
# 添加 Docker 权限
sudo usermod -aG docker zeng

# 添加 kubectl 配置
mkdir -p /home/zeng/.kube
cp /etc/rancher/k3s/k3s.yaml /home/zeng/.kube/config
chown -R zeng:zeng /home/zeng/.kube

# 配置 sudo 权限 (可选)
echo "zeng ALL=(ALL) NOPASSWD: /usr/local/bin/kubectl" | sudo tee /etc/sudoers.d/kubectl
echo "zeng ALL=(ALL) NOPASSWD: /usr/bin/docker" | sudo tee /etc/sudoers.d/docker
```

---

## 3. Docker 配置与最佳实践

### 3.1 多阶段构建策略

#### Go 后端服务 Dockerfile
```dockerfile
# docker/first-app/Dockerfile.develop
FROM golang:1.24-alpine AS builder

# 设置工作目录
WORKDIR /app

# 复制 go mod 文件
COPY backend/go.mod backend/go.sum ./

# 下载依赖
RUN go mod download

# 复制源代码
COPY backend/app/first_app/ .

# 构建应用 - 开发环境优化构建速度
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# 运行阶段
FROM alpine:latest

# 安装 ca-certificates 和调试工具
RUN apk --no-cache add ca-certificates curl

# 创建非 root 用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /app/main .

# 更改文件所有者
RUN chown -R appuser:appgroup /app

# 切换到非 root 用户
USER appuser

# 暴露端口
EXPOSE 18080

# 设置开发环境变量
ENV GIN_MODE=debug
ENV LOG_LEVEL=debug

# 运行应用
CMD ["./main"]
```

#### Node.js 前端服务 Dockerfile
```dockerfile
# docker/web-app/Dockerfile.develop
FROM node:18-alpine AS builder

# 设置工作目录
WORKDIR /app

# 复制 package 文件
COPY frontend/first_app/package*.json ./

# 安装依赖
RUN npm ci --only=production

# 复制源代码
COPY frontend/first_app/src ./src

# 运行阶段
FROM node:18-alpine

# 创建非 root 用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# 从构建阶段复制文件
COPY --from=builder /app .

# 更改文件所有者
RUN chown -R appuser:appgroup /app

# 切换到非 root 用户
USER appuser

# 暴露端口
EXPOSE 3000

# 设置环境变量
ENV NODE_ENV=development
ENV PORT=3000

# 运行应用
CMD ["node", "src/app.js"]
```

### 3.2 环境特定配置

#### 生产环境 Dockerfile 差异
```dockerfile
# docker/first-app/Dockerfile.prod
# 与开发环境的主要差异:

# 1. 构建参数优化
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o main .

# 2. 最小化运行时镜像
FROM scratch

# 3. 仅复制必要文件
COPY --from=builder /app/main /main
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# 4. 生产环境变量
ENV GIN_MODE=release
ENV LOG_LEVEL=info

# 5. 安全配置
USER 1001:1001

CMD ["/main"]
```

### 3.3 构建优化技巧

#### .dockerignore 配置
```dockerignore
# backend/.dockerignore
.git
.gitignore
README.md
Dockerfile*
.dockerignore
vendor/
bin/
*.log
.DS_Store
.env*

# frontend/.dockerignore
.git
.gitignore
README.md
Dockerfile*
.dockerignore
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.DS_Store
.env*
coverage/
.nyc_output
```

#### 构建脚本
```bash
#!/bin/bash
# scripts/build-docker.sh

set -e

APP_NAME="$1"
ENVIRONMENT="$2"
COMMIT_SHA="${3:-$(git rev-parse --short HEAD)}"

if [ -z "$APP_NAME" ] || [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <app-name> <environment> [commit-sha]"
    exit 1
fi

DOCKERFILE="docker/${APP_NAME}/Dockerfile.${ENVIRONMENT}"
IMAGE_TAG="${APP_NAME}:${COMMIT_SHA}"
ENV_TAG="${APP_NAME}:${ENVIRONMENT}-latest"

echo "Building ${APP_NAME} for ${ENVIRONMENT} environment..."
echo "Dockerfile: ${DOCKERFILE}"
echo "Image tag: ${IMAGE_TAG}"

# 构建镜像
docker build -f "${DOCKERFILE}" -t "${IMAGE_TAG}" .

# 创建环境标签
docker tag "${IMAGE_TAG}" "${ENV_TAG}"

echo "Build completed: ${IMAGE_TAG}"
echo "Environment tag: ${ENV_TAG}"

# 推送到仓库 (如果配置了)
if [ -n "$DOCKER_REGISTRY" ]; then
    docker push "${IMAGE_TAG}"
    docker push "${ENV_TAG}"
    echo "Images pushed to registry"
fi
```

---

## 4. Kubernetes 配置详解

### 4.1 命名空间和基础配置

#### 命名空间配置
```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    name: app
    environment: development
```

#### RBAC 配置 (可选)
```yaml
# k8s/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-deployer
  namespace: app
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: app-deployer-role
rules:
- apiGroups: [""]
  resources: ["namespaces", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["services", "pods"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["traefik.io"]
  resources: ["ingressroutes", "middlewares"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-deployer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: app-deployer-role
subjects:
- kind: ServiceAccount
  name: app-deployer
  namespace: app
```

### 4.2 应用配置

#### ConfigMap 配置
```yaml
# k8s/local-dev-apps.yaml (部分)
---
# ConfigMap - first-app 开发环境
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-first-app-develop-config
  namespace: app
  labels:
    app: first-app
    environment: develop
data:
  LOG_LEVEL: "debug"
  GIN_MODE: "debug"
  NODE_ENV: "development"
  PORT: "18080"
  # 自定义配置
  DATABASE_URL: "host=localhost user=app password=secret dbname=app_dev sslmode=disable"
  REDIS_URL: "redis://localhost:6379/0"
  JWT_SECRET: "dev-secret-key"
  CORS_ORIGINS: "http://localhost:3000,http://localhost:8080"
```

#### Deployment 配置
```yaml
---
# Deployment - first-app
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-first-app-develop
  namespace: app
  labels:
    app: first-app
    environment: develop
    version: develop
spec:
  replicas: 1  # 开发环境使用单副本
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: first-app
      environment: develop
  template:
    metadata:
      labels:
        app: first-app
        environment: develop
        version: develop
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "18080"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: app-deployer  # 如果使用 RBAC
      containers:
      - name: first-app
        image: first-app:8575e4a  # 这个标签会被 CI/CD 自动更新
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 18080
          name: http
          protocol: TCP
        envFrom:
        - configMapRef:
            name: app-first-app-develop-config
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        livenessProbe:
          httpGet:
            path: /ping
            port: 18080
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ping
            port: 18080
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 15"]
```

#### Service 配置
```yaml
---
# Service - first-app
apiVersion: v1
kind: Service
metadata:
  name: app-first-app-develop
  namespace: app
  labels:
    app: first-app
    environment: develop
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "18080"
spec:
  selector:
    app: first-app
    environment: develop
  ports:
  - name: http
    port: 18080
    targetPort: 18080
    protocol: TCP
  type: ClusterIP
  sessionAffinity: None
```

### 4.3 Traefik Ingress 配置

#### IngressRoute 配置
```yaml
---
# IngressRoute - first-app (Traefik v2)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app-first-app-develop
  namespace: app
  labels:
    app: first-app
    environment: develop
spec:
  entryPoints:
    - web
  routes:
  - match: PathPrefix(`/first-app`)
    kind: Rule
    services:
    - name: app-first-app-develop
      port: 18080
    middlewares:
    - name: app-first-app-stripprefix
    - name: app-first-app-headers
  priority: 10
```

#### Middleware 配置
```yaml
---
# Middleware - StripPrefix for first-app
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: app-first-app-stripprefix
  namespace: app
spec:
  stripPrefix:
    prefixes:
      - /first-app
    forceSlash: false
---
# Middleware - Custom Headers
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: app-first-app-headers
  namespace: app
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
      X-Forwarded-Host: "localhost"
    customResponseHeaders:
      X-App-Version: "develop"
      X-Environment: "development"
    accessControlAllowMethods:
      - GET
      - POST
      - PUT
      - DELETE
      - OPTIONS
    accessControlAllowOriginList:
      - "http://localhost:3000"
      - "http://localhost:8080"
    accessControlAllowHeaders:
      - Content-Type
      - Authorization
      - X-Requested-With
```

### 4.4 高级配置

#### HPA (Horizontal Pod Autoscaler)
```yaml
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-first-app-develop-hpa
  namespace: app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-first-app-develop
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

#### Network Policy
```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-first-app-develop-netpol
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: first-app
      environment: develop
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: app
    - namespaceSelector:
        matchLabels:
          name: traefik
    ports:
    - protocol: TCP
      port: 18080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: app
    - namespaceSelector:
        matchLabels:
          name: kube-system
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

---

## 5. GitHub Actions CI/CD 流水线

### 5.1 整体架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Push Event    │    │  Branch Parse   │    │   Build Docker  │
│   to Branch     │───▶│   Job           │───▶│     Image       │
│ backend-*-*     │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Verification  │◀───│  Deploy to K8s  │◀───│   Update Image  │
│   & Testing     │    │     Job         │    │     Tag         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 5.2 Workflow 配置详解

#### 主要配置文件
```yaml
# .github/workflows/deploy-monorepo.yaml
name: Deploy Monorepo by Branch Name

on:
  push:
    branches:
      - 'backend-*-*'
      - 'frontend-*-*'
  pull_request:
    branches:
      - 'backend-*-*'
      - 'frontend-*-*'
  workflow_dispatch:

env:
  REGISTRY: local
  NAMESPACE: app

jobs:
  # 1. 分支解析作业
  parse-branch:
    runs-on: self-hosted
    outputs:
      domain: ${{ steps.parse.outputs.domain }}
      app-name: ${{ steps.parse.outputs.app-name }}
      environment: ${{ steps.parse.outputs.environment }}
      app-dir: ${{ steps.parse.outputs.app-dir }}
      dockerfile: ${{ steps.parse.outputs.dockerfile }}
      service-name: ${{ steps.parse.outputs.service-name }}
      port: ${{ steps.parse.outputs.port }}
      commit-short: ${{ steps.parse.outputs.commit-short }}
      should-deploy: ${{ steps.check.outputs.should-deploy }}
    steps:
      # ... 详细步骤见后续内容

  # 2. Docker 镜像构建作业
  build:
    needs: parse-branch
    if: needs.parse-branch.outputs.should-deploy == 'true'
    runs-on: self-hosted
    outputs:
      image-tag: ${{ steps.build.outputs.image-tag }}
      build-success: ${{ steps.build.outputs.build-success }}
    steps:
      # ... 详细步骤见后续内容

  # 3. Kubernetes 部署作业
  deploy:
    needs: [parse-branch, build]
    if: |
      needs.parse-branch.outputs.should-deploy == 'true' &&
      needs.build.outputs.build-success == 'true' &&
      github.event_name == 'push'
    runs-on: self-hosted
    outputs:
      deployment-success: ${{ steps.deploy.outputs.deployment-success }}
    steps:
      # ... 详细步骤见后续内容

  # 4. 部署验证作业
  verify:
    needs: [parse-branch, deploy]
    if: |
      needs.parse-branch.outputs.should-deploy == 'true' &&
      needs.deploy.outputs.deployment-success == 'true'
    runs-on: self-hosted
    steps:
      # ... 详细步骤见后续内容

  # 5. 通知作业
  notify:
    needs: [parse-branch, build, deploy, verify]
    if: always()
    runs-on: self-hosted
    steps:
      # ... 详细步骤见后续内容
```

### 5.3 分支解析作业详解

#### 环境调试步骤
```yaml
- name: 调试环境信息
  run: |
    echo "🐛 调试信息开始"
    echo "当前工作目录: $(pwd)"
    echo "用户: $(whoami)"
    echo "环境变量:"
    env | grep GITHUB | head -10
    echo ""
    echo "目录结构:"
    ls -la
    echo ""
    echo "scripts 目录:"
    ls -la scripts/ || echo "❌ scripts 目录不存在"
    echo ""
    echo "分支名称: ${{ github.ref_name }}"
    echo "🐛 调试信息结束"
```

#### 分支解析脚本执行
```yaml
- name: 解析分支信息
  id: parse
  run: |
    BRANCH="${{ github.ref_name }}"
    echo "🔍 解析分支: $BRANCH"

    # 检查脚本文件
    echo "📋 检查脚本文件:"
    if [ -f "./scripts/parse-branch.sh" ]; then
      echo "✅ 脚本文件存在"
      echo "文件权限: $(ls -la ./scripts/parse-branch.sh)"
      echo "文件大小: $(wc -l ./scripts/parse-branch.sh)"
    else
      echo "❌ 脚本文件不存在"
      echo "当前目录内容:"
      find . -name "*.sh" -type f
      exit 1
    fi

    # 执行分支解析脚本
    echo "🚀 执行解析脚本..."
    ./scripts/parse-branch.sh "$BRANCH" > /tmp/branch-output.txt 2>&1
    SCRIPT_EXIT_CODE=$?

    echo "📋 脚本执行结果:"
    echo "退出代码: $SCRIPT_EXIT_CODE"
    echo "输出文件大小: $(wc -c /tmp/branch-output.txt)"
    echo ""

    # 显示完整输出
    echo "📄 脚本完整输出:"
    cat /tmp/branch-output.txt
    echo ""

    # 提取关键信息
    echo "🧪 开始提取变量..."
    DOMAIN=$(grep "域:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    APP_NAME=$(grep "应用名:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    ENVIRONMENT=$(grep "环境:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    APP_DIR=$(grep "应用目录:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    DOCKERFILE=$(grep "Dockerfile:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    SERVICE_NAME=$(grep "服务名:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    PORT=$(grep "端口:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")
    COMMIT_SHORT=$(grep "Commit:" /tmp/branch-output.txt | awk '{print $2}' || echo "NOT_FOUND")

    # 验证目录存在性
    if [ "$APP_DIR" != "NOT_FOUND" ] && [ -n "$APP_DIR" ]; then
      echo "📂 验证应用目录: $APP_DIR"
      if [ -d "$APP_DIR" ]; then
        echo "✅ 应用目录存在"
        echo "目录内容:"
        ls -la "$APP_DIR"
      else
        echo "❌ 应用目录不存在"
        exit 1
      fi
    fi

    # 设置输出变量
    echo "domain=$DOMAIN" >> $GITHUB_OUTPUT
    echo "app-name=$APP_NAME" >> $GITHUB_OUTPUT
    echo "environment=$ENVIRONMENT" >> $GITHUB_OUTPUT
    echo "app-dir=$APP_DIR" >> $GITHUB_OUTPUT
    echo "dockerfile=$DOCKERFILE" >> $GITHUB_OUTPUT
    echo "service-name=$SERVICE_NAME" >> $GITHUB_OUTPUT
    echo "port=$PORT" >> $GITHUB_OUTPUT
    echo "commit-short=$COMMIT_SHORT" >> $GITHUB_OUTPUT
    echo "✅ 变量设置完成"
```

#### 文件变更检查
```yaml
- name: 检查文件变更
  id: check
  run: |
    echo "🔍 检查文件变更步骤"

    # 获取前面步骤的输出
    APP_DIR="${{ steps.parse.outputs.app-dir }}"
    DOMAIN="${{ steps.parse.outputs.domain }}"
    APP_NAME="${{ steps.parse.outputs.app-name }}"
    ENVIRONMENT="${{ steps.parse.outputs.environment }}"

    echo "📋 接收到的变量:"
    echo "  APP_DIR: '$APP_DIR'"
    echo "  DOMAIN: '$DOMAIN'"
    echo "  APP_NAME: '$APP_NAME'"
    echo "  ENVIRONMENT: '$ENVIRONMENT'"
    echo ""

    # 详细的条件检查
    echo "🧪 执行条件检查..."

    # 检查 APP_DIR 是否为空
    if [ -z "$APP_DIR" ]; then
      echo "❌ APP_DIR 为空"
      echo "should-deploy=false" >> $GITHUB_OUTPUT
      echo "🚫 部署被跳过: APP_DIR 为空"
      exit 0
    fi

    # 检查 APP_DIR 是否等于 NOT_FOUND
    if [ "$APP_DIR" = "NOT_FOUND" ]; then
      echo "❌ APP_DIR 提取失败 (NOT_FOUND)"
      echo "should-deploy=false" >> $GITHUB_OUTPUT
      echo "🚫 部署被跳过: APP_DIR 提取失败"
      exit 0
    fi

    # 检查目录是否存在
    if [ ! -d "$APP_DIR" ]; then
      echo "❌ 应用目录不存在: $APP_DIR"
      echo "📂 当前目录结构:"
      find . -name "*app*" -type d | head -10
      echo "should-deploy=false" >> $GITHUB_OUTPUT
      echo "🚫 部署被跳过: 应用目录不存在"
      exit 0
    fi

    # 所有检查通过
    echo "✅ 所有检查通过"
    echo "✅ 找到应用目录: $APP_DIR"
    echo "should-deploy=true" >> $GITHUB_OUTPUT
    echo "🚀 准备部署"
```

### 5.4 Docker 构建作业详解

```yaml
- name: 构建 Docker 镜像
  id: build
  run: |
    APP_NAME="${{ needs.parse-branch.outputs.app-name }}"
    ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
    DOCKERFILE="${{ needs.parse-branch.outputs.dockerfile }}"
    COMMIT_SHORT="${{ needs.parse-branch.outputs.commit-short }}"

    echo "🐳 构建镜像: $APP_NAME"
    echo "Dockerfile: $DOCKERFILE"
    echo "标签: $COMMIT_SHORT"

    # 检查 Dockerfile 是否存在
    if [ ! -f "$DOCKERFILE" ]; then
      echo "❌ Dockerfile 不存在: $DOCKERFILE"
      echo "build-success=false" >> $GITHUB_OUTPUT
      exit 1
    fi

    # 构建镜像
    IMAGE_TAG="${APP_NAME}:${COMMIT_SHORT}"
    ENV_TAG="${APP_NAME}:${ENVIRONMENT}-latest"

    echo "🔨 开始构建: $IMAGE_TAG"
    docker build -f "$DOCKERFILE" -t "$IMAGE_TAG" .

    # 创建环境标签
    docker tag "$IMAGE_TAG" "$ENV_TAG"

    echo "image-tag=$IMAGE_TAG" >> $GITHUB_OUTPUT
    echo "build-success=true" >> $GITHUB_OUTPUT

    echo "✅ 镜像构建完成"
    docker images | grep "$APP_NAME"
```

### 5.5 Kubernetes 部署作业详解

#### kubectl 安装和配置
```yaml
- name: 安装 kubectl 和配置环境
  run: |
    echo "🔧 安装 kubectl 和配置 Kubernetes 环境"

    # 安装 kubectl
    echo "📦 安装 kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    # 验证安装
    echo "✅ kubectl 安装完成"
    kubectl version --client
    echo ""

    # 设置环境变量
    echo "🔧 配置环境变量..."
    export KUBECONFIG=/home/zeng/.kube/config
    echo "KUBECONFIG=$KUBECONFIG" >> $GITHUB_ENV
    echo "✅ 环境变量配置完成"
    echo ""

    # 验证 kubeconfig 文件
    echo "📁 验证 kubeconfig 文件..."
    if [ -f "$KUBECONFIG" ]; then
      echo "✅ kubeconfig 文件存在: $KUBECONFIG"
      echo "文件权限: $(ls -la $KUBECONFIG)"
      echo "当前上下文: $(kubectl config current-context)"
    else
      echo "❌ kubeconfig 文件不存在: $KUBECONFIG"
      exit 1
    fi
    echo "🔧 kubectl 环境配置完成"
```

#### Kubernetes 连接诊断
```yaml
- name: Kubernetes 连接诊断
  run: |
    echo "🔍 Kubernetes 连接诊断开始"

    # 基本信息
    echo "📋 基本信息:"
    echo "当前用户: $(whoami)"
    echo "工作目录: $(pwd)"
    echo "kubectl 版本: $(kubectl version --client 2>/dev/null | head -n 1 || echo '未安装')"
    echo ""

    # 配置文件检查
    echo "📁 kubeconfig 配置检查:"
    if [ -f "$HOME/.kube/config" ]; then
      echo "✅ kubeconfig 文件存在: $HOME/.kube/config"
      echo "文件权限: $(ls -la $HOME/.kube/config)"
      echo "文件大小: $(wc -l < $HOME/.kube/config) 行"
    else
      echo "❌ kubeconfig 文件不存在"
      exit 1
    fi
    echo ""

    # 当前上下文
    echo "🎯 当前上下文:"
    kubectl config current-context 2>/dev/null || echo "❌ 无法获取当前上下文"
    echo ""

    # 集群连接测试
    echo "🔗 集群连接测试:"
    echo "尝试连接集群..."
    if kubectl cluster-info --request-timeout=10s 2>/dev/null; then
      echo "✅ 集群连接成功"
      echo ""
      echo "📊 集群详细信息:"
      kubectl cluster-info
      echo ""
      echo "🔧 节点状态:"
      kubectl get nodes -o wide 2>/dev/null || echo "❌ 无法获取节点信息"
      echo ""
      echo "🏷️ 可用命名空间:"
      kubectl get namespaces 2>/dev/null || echo "❌ 无法获取命名空间"
    else
      echo "❌ 集群连接失败"
      exit 1
    fi
    echo "🔍 Kubernetes 连接诊断结束"
```

#### 应用部署
```yaml
- name: 部署到 Kubernetes
  id: deploy
  run: |
    APP_NAME="${{ needs.parse-branch.outputs.app-name }}"
    ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
    SERVICE_NAME="${{ needs.parse-branch.outputs.service-name }}"
    COMMIT_SHORT="${{ needs.parse-branch.outputs.commit-short }}"
    IMAGE_TAG="${{ needs.build.outputs.image-tag }}"
    NAMESPACE="${{ env.NAMESPACE }}"

    echo "🚀 部署应用: $APP_NAME"
    echo "环境: $ENVIRONMENT"
    echo "命名空间: $NAMESPACE"
    echo "镜像: $IMAGE_TAG"

    # 验证 K8s 集群连接
    echo "🔍 最终集群连接验证..."
    if ! kubectl cluster-info --request-timeout=30s; then
      echo "❌ 无法连接到 Kubernetes 集群"
      echo "deployment-success=false" >> $GITHUB_OUTPUT
      exit 1
    fi
    echo "✅ 集群连接验证通过"

    # 确保 namespace 存在
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # 更新 K8s 配置文件中的镜像标签
    K8S_CONFIG="k8s/local-dev-apps.yaml"
    if [ -f "$K8S_CONFIG" ]; then
      echo "📝 更新 K8s 配置文件"
      echo "🔧 更新镜像: $APP_NAME 从旧版本到 $IMAGE_TAG"

      # 使用更精确的 sed 命令匹配 app-name 并更新镜像
      sed -i.bak "s|image: $APP_NAME:.*|image: $IMAGE_TAG|g" "$K8S_CONFIG"

      # 验证更新是否成功
      echo "📋 验证镜像更新结果:"
      grep "image: $APP_NAME" "$K8S_CONFIG" || echo "❌ 未找到 $APP_NAME 的镜像配置"
    else
      echo "❌ K8s 配置文件不存在: $K8S_CONFIG"
      echo "deployment-success=false" >> $GITHUB_OUTPUT
      exit 1
    fi

    # 部署应用
    echo "☸️ 部署到 Kubernetes..."
    kubectl apply -f "$K8S_CONFIG"

    # 等待部署完成
    echo "⏳ 等待部署完成..."
    DEPLOYMENT_NAME="app-${APP_NAME}-${ENVIRONMENT}"
    echo "🎯 期望的部署名称: $DEPLOYMENT_NAME"
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" --namespace="$NAMESPACE" --timeout=120s

    # 恢复备份文件
    if [ -f "$K8S_CONFIG.bak" ]; then
      mv "$K8S_CONFIG.bak" "$K8S_CONFIG"
    fi

    echo "deployment-success=true" >> $GITHUB_OUTPUT
    echo "✅ 部署完成"
```

### 5.6 部署验证作业

```yaml
- name: 验证部署状态
  run: |
    SERVICE_NAME="${{ needs.parse-branch.outputs.service-name }}"
    ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
    PORT="${{ needs.parse-branch.outputs.port }}"
    NAMESPACE="${{ env.NAMESPACE }}"

    echo "📊 验证部署状态..."

    # 检查 Pod 状态
    echo "Pod 状态:"
    kubectl get pods --namespace="$NAMESPACE" -l app="$SERVICE_NAME" -l environment="$ENVIRONMENT"

    # 检查服务状态
    echo "服务状态:"
    kubectl get services --namespace="$NAMESPACE" -l app="$SERVICE_NAME" -l environment="$ENVIRONMENT"

    # 等待服务启动
    echo "⏳ 等待服务启动..."
    sleep 10

    # 健康检查
    echo "🧪 执行健康检查..."

    # 根据应用类型进行不同的健康检查
    if [[ "$SERVICE_NAME" == *"app" ]]; then
      # 后端应用检查
      HEALTH_PATH="/${SERVICE_NAME%%-app}/ping"
      curl -f "http://localhost$HEALTH_PATH" || echo "⚠️ 健康检查失败，但部署可能仍在进行中"
    else
      # 前端应用检查
      curl -f "http://localhost/health" || echo "⚠️ 健康检查失败，但部署可能仍在进行中"
    fi

    echo "✅ 验证完成"
```

### 5.7 通知作业

```yaml
- name: 部署结果通知
  run: |
    DOMAIN="${{ needs.parse-branch.outputs.domain }}"
    APP_NAME="${{ needs.parse-branch.outputs.app-name }}"
    ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
    BRANCH="${{ github.ref_name }}"
    COMMIT="${{ github.sha }}"

    echo "📋 部署结果:"
    echo "  分支: $BRANCH"
    echo "  域: $DOMAIN"
    echo "  应用: $APP_NAME"
    echo "  环境: $ENVIRONMENT"
    echo "  Commit: $COMMIT"
    echo ""

    if [[ "${{ needs.deploy.result }}" == "success" ]]; then
      echo "🎉 部署成功!"
      echo "🌐 访问地址: http://localhost/${APP_NAME%%-app}/"
    elif [[ "${{ needs.build.result }}" == "failure" ]]; then
      echo "❌ 构建失败!"
    elif [[ "${{ needs.deploy.result }}" == "failure" ]]; then
      echo "❌ 部署失败!"
    elif [[ "${{ needs.parse-branch.outputs.should-deploy }}" == "false" ]]; then
      echo "ℹ️ 跳过部署 - 应用目录不存在或无变更。"
    else
      echo "⚠️ 未知状态"
    fi
```

---

## 6. 分支命名规范与自动化解析

### 6.1 分支命名规范

#### 命名格式
```
{domain}-{app-name}-{environment}
```

#### 支持的域名 (Domain)
- `backend` - 后端服务
- `frontend` - 前端服务

#### 环境类型 (Environment)
- `develop` - 开发环境
- `staging` - 预发布环境
- `prod` - 生产环境

#### 示例分支名称
```bash
# 后端服务分支
backend-first-app-develop    # 第一个后端应用开发环境
backend-first-app-staging    # 第一个后端应用预发布环境
backend-first-app-prod       # 第一个后端应用生产环境
backend-second-app-develop   # 第二个后端应用开发环境

# 前端服务分支
frontend-web-app-develop     # Web前端开发环境
frontend-web-app-staging     # Web前端预发布环境
frontend-web-app-prod        # Web前端生产环境
```

### 6.2 分支解析脚本详解

#### 脚本实现
```bash
#!/bin/bash
# scripts/parse-branch.sh

set -e

BRANCH_NAME="$1"

# 验证分支名称格式
if [[ ! "$BRANCH_NAME" =~ ^(backend|frontend)-[a-zA-Z0-9-]+-(develop|staging|prod)$ ]]; then
    echo "❌ 无效的分支名称格式: $BRANCH_NAME"
    echo "正确格式: {domain}-{app}-{environment}"
    echo "示例: backend-first-app-develop, frontend-web-app-staging"
    exit 1
fi

# 解析分支名称
DOMAIN=$(echo "$BRANCH_NAME" | cut -d'-' -f1)
TEMP_NAME=$(echo "$BRANCH_NAME" | cut -d'-' -f2-)

# 分离应用名和环境
if [[ "$TEMP_NAME" =~ ^(.*)-(develop|staging|prod)$ ]]; then
    APP_NAME="${BASH_REMATCH[1]}"
    ENVIRONMENT="${BASH_REMATCH[2]}"
else
    echo "❌ 无法解析应用名和环境: $TEMP_NAME"
    exit 1
fi

# 映射到目录结构
if [ "$DOMAIN" = "backend" ]; then
    APP_DIR="backend/app/${APP_NAME//-/_}"
    DOCKERFILE="docker/${APP_NAME}/Dockerfile.${ENVIRONMENT}"
    SERVICE_NAME="${APP_NAME//-/_}"
    PORT=$(echo "$APP_NAME" | grep -o '[0-9]\+' || echo "18080")
elif [ "$DOMAIN" = "frontend" ]; then
    APP_DIR="frontend/${APP_NAME//-/_}"
    DOCKERFILE="docker/${APP_NAME}/Dockerfile.${ENVIRONMENT}"
    SERVICE_NAME="${APP_NAME//-/_}"
    PORT="3000"
else
    echo "❌ 不支持的域: $DOMAIN"
    exit 1
fi

# 获取 Git short commit
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# 输出解析结果
echo "📊 分支解析结果:"
echo "  域: $DOMAIN"
echo "  应用名: $APP_NAME"
echo "  环境: $ENVIRONMENT"
echo "  应用目录: $APP_DIR"
echo "  Dockerfile: $DOCKERFILE"
echo "  服务名: $SERVICE_NAME"
echo "  端口: $PORT"
echo "  Commit: $COMMIT_SHORT"

# 输出环境变量（供 GitHub Actions 使用）
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "domain=$DOMAIN" >> $GITHUB_OUTPUT
    echo "app-name=$APP_NAME" >> $GITHUB_OUTPUT
    echo "environment=$ENVIRONMENT" >> $GITHUB_OUTPUT
    echo "app-dir=$APP_DIR" >> $GITHUB_OUTPUT
    echo "dockerfile=$DOCKERFILE" >> $GITHUB_OUTPUT
    echo "service-name=$SERVICE_NAME" >> $GITHUB_OUTPUT
    echo "port=$PORT" >> $GITHUB_OUTPUT
    echo "commit-short=$COMMIT_SHORT" >> $GITHUB_OUTPUT
else
    echo "ℹ️ 本地运行模式 - GitHub Actions 输出跳过"
fi
```

#### 目录映射规则
```bash
# 后端应用映射
backend-first-app-develop  →  backend/app/first_app
backend-second-app-develop →  backend/app/second_app

# 前端应用映射
frontend-web-app-develop   →  frontend/web_app

# Dockerfile 映射
first-app → docker/first-app/Dockerfile.{environment}
second-app → docker/second-app/Dockerfile.{environment}
web-app → docker/web-app/Dockerfile.{environment}
```

### 6.3 自动化部署逻辑

#### 触发条件
```yaml
# GitHub Actions 触发条件
on:
  push:
    branches:
      - 'backend-*-*'      # 后端分支推送时触发
      - 'frontend-*-*'     # 前端分支推送时触发
  pull_request:
    branches:
      - 'backend-*-*'      # 后端分支 PR 时触发
      - 'frontend-*-*'     # 前端分支 PR 时触发
  workflow_dispatch:       # 手动触发
```

#### 部署条件判断
```bash
# 在 GitHub Actions 中的条件判断
if [[ "${{ github.event_name }}" == "push" ]]; then
    # 推送事件时执行完整部署
    deploy_to_kubernetes
elif [[ "${{ github.event_name }}" == "pull_request" ]]; then
    # PR 事件时只构建和测试，不部署
    build_and_test_only
fi
```

#### 环境隔离
```yaml
# 不同环境使用不同的命名空间
namespace_map:
  develop: "app-develop"
  staging: "app-staging"
  prod: "app-prod"

# 不同环境使用不同的资源配置
resource_limits:
  develop:
    memory: "128Mi"
    cpu: "100m"
    replicas: 1
  staging:
    memory: "256Mi"
    cpu: "200m"
    replicas: 2
  prod:
    memory: "512Mi"
    cpu: "500m"
    replicas: 3
```

---

## 7. 部署验证与监控

### 7.1 健康检查配置

#### 应用健康检查端点

##### Go 后端应用
```go
// backend/app/first_app/main.go
package main

import (
    "github.com/gin-gonic/gin"
    "net/http"
)

func main() {
    r := gin.Default()

    // 健康检查端点
    r.GET("/ping", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{
            "status": "ok",
            "service": "first-app",
            "version": "1.0.0",
        })
    })

    // 就绪检查端点
    r.GET("/ready", func(c *gin.Context) {
        // 检查依赖服务状态
        c.JSON(http.StatusOK, gin.H{
            "status": "ready",
            "database": "connected",
            "redis": "connected",
        })
    })

    // 存活检查端点
    r.GET("/live", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{
            "status": "live",
            "uptime": "123s",
        })
    })

    r.Run(":18080")
}
```

##### Node.js 前端应用
```javascript
// frontend/first_app/src/app.js
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// 健康检查端点
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'web-app',
        version: process.env.VERSION || '1.0.0',
        uptime: process.uptime(),
        environment: process.env.NODE_ENV || 'development'
    });
});

// 就绪检查端点
app.get('/ready', (req, res) => {
    res.json({
        status: 'ready',
        dependencies: 'all-connected'
    });
});

// 存活检查端点
app.get('/live', (req, res) => {
    res.json({
        status: 'live',
        timestamp: new Date().toISOString()
    });
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
```

### 7.2 Kubernetes 健康检查配置

#### Pod 健康检查
```yaml
# 在 Deployment 配置中
livenessProbe:
  httpGet:
    path: /ping
    port: 18080
    scheme: HTTP
  initialDelaySeconds: 10    # 容器启动后延迟10秒开始检查
  periodSeconds: 30         # 每30秒检查一次
  timeoutSeconds: 5         # 检查超时时间
  failureThreshold: 3       # 连续3次失败后重启
  successThreshold: 1       # 成功1次即认为健康

readinessProbe:
  httpGet:
    path: /ready
    port: 18080
    scheme: HTTP
  initialDelaySeconds: 5     # 容器启动后延迟5秒开始检查
  periodSeconds: 10         # 每10秒检查一次
  timeoutSeconds: 3         # 检查超时时间
  failureThreshold: 3       # 连续3次失败后标记为未就绪
  successThreshold: 1       # 成功1次即认为就绪
```

#### 启动探针 (Startup Probe)
```yaml
startupProbe:
  httpGet:
    path: /health
    port: 18080
    scheme: HTTP
  initialDelaySeconds: 10    # 容器启动后延迟10秒开始检查
  periodSeconds: 10         # 每10秒检查一次
  timeoutSeconds: 5         # 检查超时时间
  failureThreshold: 30      # 最多允许30次失败 (300秒总时间)
  successThreshold: 1       # 成功1次即认为启动完成
```

### 7.3 部署验证脚本

#### 自动化验证脚本
```bash
#!/bin/bash
# scripts/verify-deployment.sh

set -e

APP_NAME="$1"
ENVIRONMENT="$2"
NAMESPACE="${3:-app}"
TIMEOUT="${4:-300}"

echo "🔍 开始验证部署..."
echo "应用: $APP_NAME"
echo "环境: $ENVIRONMENT"
echo "命名空间: $NAMESPACE"
echo "超时: ${TIMEOUT}s"

# 等待部署完成
echo "⏳ 等待部署 rollout 完成..."
DEPLOYMENT_NAME="app-${APP_NAME}-${ENVIRONMENT}"

if ! kubectl rollout status deployment/"$DEPLOYMENT_NAME" \
    --namespace="$NAMESPACE" \
    --timeout="${TIMEOUT}s"; then
    echo "❌ 部署 rollout 失败"
    exit 1
fi

echo "✅ Rollout 完成"

# 检查 Pod 状态
echo "📋 检查 Pod 状态..."
kubectl get pods --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT" \
    --show-labels

# 检查 Pod 是否就绪
READY_PODS=$(kubectl get pods --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT" \
    -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | tr ' ' '\n' | grep -c true || echo "0")

TOTAL_PODS=$(kubectl get pods --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT" \
    --no-headers | wc -l)

echo "Pod 就绪状态: $READY_PODS/$TOTAL_PODS"

if [ "$READY_PODS" -eq 0 ] || [ "$READY_PODS" -ne "$TOTAL_PODS" ]; then
    echo "❌ Pod 未全部就绪"
    exit 1
fi

# 检查服务状态
echo "🌐 检查服务状态..."
kubectl get services --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT"

# 获取服务端口
SERVICE_PORT=$(kubectl get service "app-${APP_NAME}-${ENVIRONMENT}" \
    --namespace="$NAMESPACE" \
    -o jsonpath='{.spec.ports[0].port}')

# 等待服务可访问
echo "⏳ 等待服务可访问..."
for i in $(seq 1 30); do
    if kubectl run "test-$RANDOM" \
        --image=curlimages/curl \
        --rm -i --restart=Never \
        --namespace="$NAMESPACE" \
        -- curl -f "http://app-${APP_NAME}-${ENVIRONMENT}:${SERVICE_PORT}/ping"; then
        echo "✅ 服务可访问"
        break
    fi

    if [ $i -eq 30 ]; then
        echo "❌ 服务不可访问"
        exit 1
    fi

    echo "等待服务启动... ($i/30)"
    sleep 10
done

# 检查 Ingress 状态
echo "🚪 检查 Ingress 状态..."
kubectl get ingressroutes --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT"

# 外部访问测试
echo "🌍 外部访问测试..."
INGRESS_HOST="localhost"
INGRESS_PATH="/${APP_NAME}"

for i in $(seq 1 30); do
    if curl -f "http://${INGRESS_HOST}${INGRESS_PATH}/ping"; then
        echo "✅ 外部访问正常"
        break
    fi

    if [ $i -eq 30 ]; then
        echo "⚠️ 外部访问失败，但内部服务正常"
        break
    fi

    echo "等待 Ingress 生效... ($i/30)"
    sleep 10
done

# 检查日志
echo "📋 检查应用日志..."
kubectl logs --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT" \
    --tail=20

echo "✅ 部署验证完成"
```

### 7.4 监控配置

#### Prometheus 监控配置
```yaml
# monitoring/prometheus-config.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - "alert_rules.yml"

    scrape_configs:
      # Kubernetes 服务发现
      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
        - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
          action: keep
          regex: default;kubernetes;https

      # 应用监控
      - job_name: 'app-metrics'
        kubernetes_sd_configs:
        - role: endpoints
          namespaces:
            names:
            - app
        relabel_configs:
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__
        - action: labelmap
          regex: __meta_kubernetes_service_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_service_name]
          action: replace
          target_label: kubernetes_name
```

#### 告警规则配置
```yaml
# monitoring/alert-rules.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: alert-rules
  namespace: monitoring
data:
  alert_rules.yml: |
    groups:
    - name: app.rules
      rules:
      # Pod 重启告警
      - alert: PodRestartHigh
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod {{ $labels.pod }} is restarting frequently"
          description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is restarting {{ $value }} times per second."

      # CPU 使用率告警
      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total[5m]) * 100 > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.pod }}"
          description: "CPU usage is above 80% for more than 10 minutes."

      # 内存使用率告警
      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage on {{ $labels.pod }}"
          description: "Memory usage is above 90% for more than 5 minutes."

      # 服务不可用告警
      - alert: ServiceDown
        expr: up{job="app-metrics"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.kubernetes_name }} is down"
          description: "Service {{ $labels.kubernetes_name }} has been down for more than 2 minutes."
```

#### Grafana Dashboard 配置
```yaml
# monitoring/grafana-dashboard.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-app
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  app-dashboard.json: |
    {
      "dashboard": {
        "title": "Application Monitoring Dashboard",
        "panels": [
          {
            "title": "Pod Status",
            "type": "stat",
            "targets": [
              {
                "expr": "kube_pod_status_phase{namespace=\"app\"}",
                "legendFormat": "{{ phase }}"
              }
            ]
          },
          {
            "title": "CPU Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(container_cpu_usage_seconds_total{namespace=\"app\"}[5m]) * 100",
                "legendFormat": "{{ pod }}"
              }
            ]
          },
          {
            "title": "Memory Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "container_memory_usage_bytes{namespace=\"app\"} / 1024 / 1024",
                "legendFormat": "{{ pod }}"
              }
            ]
          },
          {
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(http_requests_total{namespace=\"app\"}[5m])",
                "legendFormat": "{{ service }}"
              }
            ]
          },
          {
            "title": "Response Time",
            "type": "graph",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{namespace=\"app\"}[5m]))",
                "legendFormat": "95th percentile - {{ service }}"
              }
            ]
          }
        ]
      }
    }
```

---

## 8. 问题排查与故障排除

### 8.1 常见问题及解决方案

#### 问题 1: GitHub Runner 配置问题

**症状**:
- Runner 无法连接到 GitHub
- Docker 权限不足
- kubectl 命令找不到

**解决方案**:
```bash
# 检查 Runner 状态
sudo ./svc.sh status

# 重启 Runner
sudo ./svc.sh stop
sudo ./svc.sh start

# 检查 Docker 权限
sudo usermod -aG docker zeng
newgrp docker

# 安装 kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# 验证 kubectl 配置
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chown -R zeng:zeng ~/.kube
```

#### 问题 2: Kubernetes 集群连接问题

**症状**:
- `kubectl cluster-info` 失败
- `The connection to the server localhost:8080 was refused`
- 权限被拒绝

**诊断步骤**:
```bash
# 检查集群状态
sudo k3s kubectl get nodes
sudo k3s kubectl get pods --all-namespaces

# 检查服务状态
sudo systemctl status k3s

# 检查配置文件
ls -la ~/.kube/config
cat ~/.kube/config

# 测试连接
kubectl cluster-info --request-timeout=10s
kubectl get namespaces
```

**解决方案**:
```bash
# 重启 k3s 服务
sudo systemctl restart k3s

# 重新配置 kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown zeng:zeng ~/.kube/config
sed -i 's/127.0.0.1/localhost/g' ~/.kube/config

# 检查防火墙
sudo ufw status
sudo ufw allow 6443/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

#### 问题 3: Docker 镜像构建失败

**症状**:
- 构建过程中权限被拒绝
- 依赖下载失败
- 镜像标签错误

**诊断脚本**:
```bash
#!/bin/bash
# scripts/debug-docker-build.sh

APP_NAME="$1"
DOCKERFILE="$2"

echo "🔍 Docker 构建诊断开始..."
echo "应用: $APP_NAME"
echo "Dockerfile: $DOCKERFILE"

# 检查 Docker 服务
echo "📋 Docker 服务状态:"
sudo systemctl status docker --no-pager

# 检查 Docker 权限
echo "👤 Docker 用户权限:"
groups $USER | grep docker || echo "❌ 用户不在 docker 组中"

# 检查 Dockerfile
echo "📄 Dockerfile 检查:"
if [ -f "$DOCKERFILE" ]; then
    echo "✅ Dockerfile 存在: $DOCKERFILE"
    echo "文件权限: $(ls -la $DOCKERFILE)"
    echo "文件内容预览:"
    head -10 "$DOCKERFILE"
else
    echo "❌ Dockerfile 不存在: $DOCKERFILE"
    echo "当前目录 Dockerfile:"
    find . -name "Dockerfile*" -type f
fi

# 检查构建上下文
echo "📂 构建上下文检查:"
echo "当前目录: $(pwd)"
echo "目录内容:"
ls -la

# 检查磁盘空间
echo "💾 磁盘空间:"
df -h

# 检查 Docker 镜像
echo "🐳 Docker 镜像:"
docker images | head -10

echo "🔍 Docker 构建诊断结束"
```

**解决方案**:
```bash
# 清理 Docker 缓存
docker system prune -f

# 修复权限问题
sudo chown -R zeng:zeng /var/run/docker.sock

# 使用详细日志重新构建
docker build -f "$DOCKERFILE" -t "${APP_NAME}:debug" . --progress=plain

# 检查网络连接
ping registry-1.docker.io
nslookup registry-1.docker.io
```

#### 问题 4: 部署名称不匹配

**症状**:
- `deployment.apps "app-first-app-develop" not found`
- Rollout status 超时
- Pod 无法启动

**诊断脚本**:
```bash
#!/bin/bash
# scripts/debug-deployment-name.sh

APP_NAME="$1"
ENVIRONMENT="$2"
NAMESPACE="$3"

echo "🔍 部署名称诊断..."
echo "应用: $APP_NAME"
echo "环境: $ENVIRONMENT"
echo "命名空间: $NAMESPACE"

# 期望的部署名称
EXPECTED_DEPLOYMENT="app-${APP_NAME}-${ENVIRONMENT}"
echo "期望部署名称: $EXPECTED_DEPLOYMENT"

# 列出所有部署
echo "📋 所有部署:"
kubectl get deployments --namespace="$NAMESPACE"

# 查找相关部署
echo "🔍 查找相关部署:"
kubectl get deployments --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT" \
    --show-labels

# 检查配置文件
echo "📄 检查配置文件..."
if [ -f "k8s/local-dev-apps.yaml" ]; then
    echo "✅ 配置文件存在"
    grep -A 5 -B 5 "name:.*${APP_NAME}" k8s/local-dev-apps.yaml || echo "❌ 未找到相关配置"
else
    echo "❌ 配置文件不存在"
fi

# 列出所有 Pod
echo "📦 所有 Pod:"
kubectl get pods --namespace="$NAMESPACE" \
    -l app="$APP_NAME" \
    -l environment="$ENVIRONMENT" \
    --show-labels

echo "🔍 部署名称诊断结束"
```

**解决方案**:
```bash
# 修正部署名称
kubectl patch deployment "old-deployment-name" \
    --namespace="$NAMESPACE" \
    -p '{"metadata":{"name":"app-first-app-develop"}}'

# 或者重新应用配置
kubectl apply -f k8s/local-dev-apps.yaml

# 等待部署完成
kubectl rollout status deployment/"app-first-app-develop" \
    --namespace="$NAMESPACE" \
    --timeout=120s
```

#### 问题 5: 镜像标签更新失败

**症状**:
- 镜像标签未被正确更新
- 部署使用旧版本镜像
- sed 命令执行失败

**诊断和修复**:
```bash
#!/bin/bash
# scripts/fix-image-tag.sh

APP_NAME="$1"
NEW_TAG="$2"
K8S_CONFIG="${3:-k8s/local-dev-apps.yaml}"

echo "🔧 修复镜像标签..."
echo "应用: $APP_NAME"
echo "新标签: $NEW_TAG"
echo "配置文件: $K8S_CONFIG"

# 备份原文件
if [ -f "$K8S_CONFIG" ]; then
    cp "$K8S_CONFIG" "${K8S_CONFIG}.backup.$(date +%s)"
    echo "✅ 已备份原文件"
else
    echo "❌ 配置文件不存在: $K8S_CONFIG"
    exit 1
fi

# 查找当前镜像标签
echo "🔍 当前镜像标签:"
grep "image: $APP_NAME:" "$K8S_CONFIG" || echo "❌ 未找到 $APP_NAME 的镜像配置"

# 更新镜像标签
echo "🔄 更新镜像标签..."
sed -i "s|image: $APP_NAME:.*|image: $NEW_TAG|g" "$K8S_CONFIG"

# 验证更新结果
echo "✅ 更新后镜像标签:"
grep "image: $APP_NAME:" "$K8S_CONFIG"

# 应用配置
echo "🚀 应用配置..."
kubectl apply -f "$K8S_CONFIG"

# 重启部署
echo "🔄 重启部署..."
DEPLOYMENT_NAME="app-${APP_NAME}-develop"
kubectl rollout restart deployment/"$DEPLOYMENT_NAME" --namespace=app

echo "✅ 镜像标签修复完成"
```

### 8.2 日志收集和分析

#### 收集所有相关日志
```bash
#!/bin/bash
# scripts/collect-logs.sh

NAMESPACE="app"
OUTPUT_DIR="logs-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUTPUT_DIR"

echo "📋 收集日志到 $OUTPUT_DIR"

# 收集 Kubernetes 事件
echo "📝 收集 Kubernetes 事件..."
kubectl get events --namespace="$NAMESPACE" > "$OUTPUT_DIR/events.txt"

# 收集 Pod 日志
echo "📦 收集 Pod 日志..."
kubectl get pods --namespace="$NAMESPACE" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers | while read pod node; do
    pod_name=$(echo $pod | awk '{print $1}')
    kubectl logs --namespace="$NAMESPACE" "$pod_name" --all-containers=true > "$OUTPUT_DIR/pod-${pod_name}.log" 2>&1
done

# 收集部署状态
echo "🚀 收集部署状态..."
kubectl get deployments --namespace="$NAMESPACE" -o wide > "$OUTPUT_DIR/deployments.txt"
kubectl describe deployments --namespace="$NAMESPACE" > "$OUTPUT_DIR/deployments-describe.txt"

# 收集服务状态
echo "🌐 收集服务状态..."
kubectl get services --namespace="$NAMESPACE" -o wide > "$OUTPUT_DIR/services.txt"
kubectl describe services --namespace="$NAMESPACE" > "$OUTPUT_DIR/services-describe.txt"

# 收集 Ingress 状态
echo "🚪 收集 Ingress 状态..."
kubectl get ingressroutes --namespace="$NAMESPACE" -o wide > "$OUTPUT_DIR/ingress.txt"
kubectl describe ingressroutes --namespace="$NAMESPACE" > "$OUTPUT_DIR/ingress-describe.txt"

# 收集节点信息
echo "🖥️ 收集节点信息..."
kubectl get nodes -o wide > "$OUTPUT_DIR/nodes.txt"
kubectl describe nodes > "$OUTPUT_DIR/nodes-describe.txt"

# 收集系统信息
echo "🖥️ 收集系统信息..."
kubectl top nodes > "$OUTPUT_DIR/nodes-metrics.txt" 2>/dev/null || echo "metrics-server not available"
kubectl top pods --namespace="$NAMESPACE" > "$OUTPUT_DIR/pods-metrics.txt" 2>/dev/null || echo "metrics-server not available"

echo "✅ 日志收集完成: $OUTPUT_DIR"
tar -czf "${OUTPUT_DIR}.tar.gz" "$OUTPUT_DIR"
```

#### 日志分析脚本
```bash
#!/bin/bash
# scripts/analyze-logs.sh

LOG_DIR="$1"

if [ -z "$LOG_DIR" ] || [ ! -d "$LOG_DIR" ]; then
    echo "❌ 请提供有效的日志目录"
    echo "Usage: $0 <log-directory>"
    exit 1
fi

echo "🔍 分析日志: $LOG_DIR"

# 分析错误
echo "❌ 分析错误..."
grep -r -i "error\|fail\|exception" "$LOG_DIR" | head -20

# 分析警告
echo "⚠️ 分析警告..."
grep -r -i "warn\|warning" "$LOG_DIR" | head -10

# 分析重启
echo "🔄 分析重启..."
grep -r -i "restart\|restarting" "$LOG_DIR" | head -10

# 分析连接问题
echo "🔗 分析连接问题..."
grep -r -i "connection\|timeout\|refused" "$LOG_DIR" | head -10

# 分析镜像问题
echo "🐳 分析镜像问题..."
grep -r -i "image\|pull\|registry" "$LOG_DIR" | head -10

echo "✅ 日志分析完成"
```

### 8.3 性能问题排查

#### 资源使用监控
```bash
#!/bin/bash
# scripts/performance-check.sh

NAMESPACE="app"

echo "📊 性能检查..."

# 检查 Pod 资源使用
echo "📈 Pod 资源使用..."
kubectl top pods --namespace="$NAMESPACE" 2>/dev/null || echo "❌ metrics-server 不可用"

# 检查节点资源使用
echo "🖥️ 节点资源使用..."
kubectl top nodes 2>/dev/null || echo "❌ metrics-server 不可用"

# 检查资源限制
echo "⚡ 资源限制检查..."
kubectl describe pods --namespace="$NAMESPACE" | grep -A 10 -B 5 "Limits\|Requests"

# 检查网络连接
echo "🌐 网络连接检查..."
kubectl exec -it $(kubectl get pods --namespace="$NAMESPACE" -o jsonpath='{.items[0].metadata.name}') \
    --namespace="$NAMESPACE" -- \
    sh -c "cat /proc/net/dev" 2>/dev/null || echo "❌ 无法获取网络信息"

# 检查磁盘使用
echo "💾 磁盘使用检查..."
kubectl exec -it $(kubectl get pods --namespace="$NAMESPACE" -o jsonpath='{.items[0].metadata.name}') \
    --namespace="$NAMESPACE" -- \
    sh -c "df -h" 2>/dev/null || echo "❌ 无法获取磁盘信息"

echo "✅ 性能检查完成"
```

### 8.4 自动化故障排除脚本

#### 综合诊断脚本
```bash
#!/bin/bash
# scripts/comprehensive-diagnosis.sh

APP_NAME="$1"
ENVIRONMENT="$2"
NAMESPACE="${3:-app}"

if [ -z "$APP_NAME" ] || [ -z "$ENVIRONMENT" ]; then
    echo "❌ 请提供应用名称和环境"
    echo "Usage: $0 <app-name> <environment> [namespace]"
    exit 1
fi

echo "🏥 综合诊断开始..."
echo "应用: $APP_NAME"
echo "环境: $ENVIRONMENT"
echo "命名空间: $NAMESPACE"

# 1. 基础检查
echo "📋 1. 基础检查"
echo "集群状态:"
kubectl cluster-info --request-timeout=10s || echo "❌ 集群连接失败"

echo "命名空间:"
kubectl get namespace "$NAMESPACE" || echo "❌ 命名空间不存在"

# 2. 部署状态检查
echo "🚀 2. 部署状态检查"
DEPLOYMENT_NAME="app-${APP_NAME}-${ENVIRONMENT}"

echo "部署状态:"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace="$NAMESPACE" || echo "❌ 部署不存在"

echo "部署详情:"
kubectl describe deployment "$DEPLOYMENT_NAME" --namespace="$NAMESPACE" | head -20

# 3. Pod 状态检查
echo "📦 3. Pod 状态检查"
echo "Pod 列表:"
kubectl get pods --namespace="$NAMESPACE" -l app="$APP_NAME" -l environment="$ENVIRONMENT"

echo "Pod 详情:"
kubectl get pods --namespace="$NAMESPACE" -l app="$APP_NAME" -l environment="$ENVIRONMENT" -o wide

# 4. 服务状态检查
echo "🌐 4. 服务状态检查"
SERVICE_NAME="app-${APP_NAME}-${ENVIRONMENT}"

echo "服务状态:"
kubectl get service "$SERVICE_NAME" --namespace="$NAMESPACE" || echo "❌ 服务不存在"

echo "服务详情:"
kubectl describe service "$SERVICE_NAME" --namespace="$NAMESPACE" | head -20

# 5. 网络连接检查
echo "🔗 5. 网络连接检查"
echo "Ingress 状态:"
kubectl get ingressroutes --namespace="$NAMESPACE" -l app="$APP_NAME" -l environment="$ENVIRONMENT"

echo "端点状态:"
kubectl get endpoints --namespace="$NAMESPACE" -l app="$APP_NAME" -l environment="$ENVIRONMENT"

# 6. 事件检查
echo "📅 6. 事件检查"
echo "最近事件:"
kubectl get events --namespace="$NAMESPACE" --sort-by='.lastTimestamp' | tail -20

# 7. 日志检查
echo "📝 7. 日志检查"
POD_NAME=$(kubectl get pods --namespace="$NAMESPACE" -l app="$APP_NAME" -l environment="$ENVIRONMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    echo "Pod 日志 ($POD_NAME):"
    kubectl logs "$POD_NAME" --namespace="$NAMESPACE" --tail=50
else
    echo "❌ 无可用 Pod"
fi

# 8. 健康检查
echo "🏥 8. 健康检查"
if [ -n "$POD_NAME" ]; then
    echo "Pod 健康状态:"
    kubectl get pod "$POD_NAME" --namespace="$NAMESPACE" -o jsonpath='{.status.conditions[*].type}: {.status}'
    echo ""

    echo "容器状态:"
    kubectl get pod "$POD_NAME" --namespace="$NAMESPACE" -o jsonpath='{.status.containerStatuses[*].state}'
    echo ""
fi

# 9. 资源使用检查
echo "📊 9. 资源使用检查"
echo "资源请求和限制:"
kubectl describe pod "$POD_NAME" --namespace="$NAMESPACE" | grep -A 10 -B 5 "Limits\|Requests" 2>/dev/null || echo "❌ 无法获取资源信息"

echo "当前资源使用:"
kubectl top pod "$POD_NAME" --namespace="$NAMESPACE" 2>/dev/null || echo "❌ metrics-server 不可用"

# 10. 生成诊断报告
echo "📋 10. 生成诊断报告"
REPORT_FILE="diagnosis-${APP_NAME}-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).txt"

{
    echo "诊断报告 - $(date)"
    echo "=========================="
    echo "应用: $APP_NAME"
    echo "环境: $ENVIRONMENT"
    echo "命名空间: $NAMESPACE"
    echo ""

    echo "部署状态:"
    kubectl get deployment "$DEPLOYMENT_NAME" --namespace="$NAMESPACE" 2>&1
    echo ""

    echo "Pod 状态:"
    kubectl get pods --namespace="$NAMESPACE" -l app="$APP_NAME" -l environment="$ENVIRONMENT" 2>&1
    echo ""

    echo "最近事件:"
    kubectl get events --namespace="$NAMESPACE" --sort-by='.lastTimestamp' | tail -10 2>&1
    echo ""

    echo "建议的修复步骤:"
    echo "1. 检查镜像是否正确构建"
    echo "2. 验证配置文件语法"
    echo "3. 确认资源限制设置合理"
    echo "4. 检查网络连接和防火墙"
    echo "5. 查看详细的应用日志"

} > "$REPORT_FILE"

echo "✅ 诊断完成，报告已保存到: $REPORT_FILE"

# 提供快速修复建议
echo ""
echo "🔧 快速修复建议:"
echo "如果部署失败，尝试以下命令:"
echo "kubectl delete deployment $DEPLOYMENT_NAME --namespace=$NAMESPACE"
echo "kubectl apply -f k8s/local-dev-apps.yaml"
echo ""
echo "如果 Pod 无法启动，尝试:"
echo "kubectl describe pod $POD_NAME --namespace=$NAMESPACE"
echo "kubectl logs $POD_NAME --namespace=$NAMESPACE"
```

---

## 9. 最佳实践总结

### 9.1 开发最佳实践

#### 分支管理
```bash
# 推荐的分支命名规范
backend-first-app-develop    # 开发环境
backend-first-app-staging    # 预发布环境
backend-first-app-prod       # 生产环境

# 分支保护规则
- 主分支禁止直接推送
- 必须通过 PR 合并
- 需要通过 CI 检查
- 需要代码审查
```

#### 代码结构
```
project/
├── backend/
│   ├── app/
│   │   ├── first_app/
│   │   │   ├── main.go           # 主程序
│   │   │   ├── handlers/         # 处理器
│   │   │   ├── models/          # 数据模型
│   │   │   ├── services/        # 业务逻辑
│   │   │   └── utils/           # 工具函数
│   │   └── second_app/
│   ├── tests/                   # 测试文件
│   ├── docs/                    # 文档
│   └── scripts/                 # 脚本文件
├── frontend/
│   └── first_app/
│       ├── src/
│       │   ├── components/      # 组件
│       │   ├── services/        # API 服务
│       │   ├── utils/           # 工具函数
│       │   └── styles/          # 样式文件
│       ├── tests/               # 测试文件
│       └── public/              # 静态资源
```

#### 环境配置
```yaml
# 配置管理最佳实践
1. 使用 ConfigMap 管理配置
2. 敏感信息使用 Secret
3. 不同环境使用不同的命名空间
4. 配置文件模板化
5. 版本化配置管理
```

### 9.2 Docker 最佳实践

#### 镜像优化
```dockerfile
# 1. 使用多阶段构建
FROM golang:1.24-alpine AS builder
# 构建步骤...

FROM alpine:latest
# 运行时镜像...

# 2. 最小化镜像层
RUN apk add --no-cache ca-certificates && \
    adduser -D -s /bin/sh appuser

# 3. 使用 .dockerignore
# .dockerignore
.git
.gitignore
README.md
vendor/
*.log
```

#### 安全配置
```dockerfile
# 1. 使用非 root 用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup
USER appuser

# 2. 最小化权限
COPY --from=builder /app/main .
chmod 500 main

# 3. 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:18080/ping || exit 1
```

### 9.3 Kubernetes 最佳实践

#### 资源管理
```yaml
# 1. 设置资源限制
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

# 2. 使用 HPA 自动扩缩容
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

#### 安全配置
```yaml
# 1. 使用安全上下文
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  fsGroup: 1001
  capabilities:
    drop:
    - ALL

# 2. 网络策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-netpol
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: app
```

#### 健康检查
```yaml
# 1. 存活探针
livenessProbe:
  httpGet:
    path: /live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

# 2. 就绪探针
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

# 3. 启动探针
startupProbe:
  httpGet:
    path: /startup
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
```

### 9.4 CI/CD 最佳实践

#### 流水线设计
```yaml
# 1. 阶段化流水线
stages:
  - validate     # 验证阶段
  - test         # 测试阶段
  - build        # 构建阶段
  - deploy       # 部署阶段
  - verify       # 验证阶段

# 2. 并行执行策略
jobs:
  test:
    strategy:
      matrix:
        go-version: [1.23, 1.24]
        os: [ubuntu-latest, windows-latest]

# 3. 缓存优化
- name: Cache Go modules
  uses: actions/cache@v3
  with:
    path: ~/go/pkg/mod
    key: ${{ runner.os }}-go-${{ hashFiles('**/go.sum') }}
```

#### 环境管理
```yaml
# 1. 环境隔离
environments:
  development:
    url: http://dev.example.com
  staging:
    url: http://staging.example.com
  production:
    url: http://example.com

# 2. 秘密管理
secrets:
  DOCKER_REGISTRY_PASSWORD:
    required: true
  KUBE_CONFIG:
    required: true

# 3. 环境变量策略
env:
  NODE_ENV: ${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
  API_URL: ${{ github.ref == 'refs/heads/main' && secrets.PROD_API_URL || secrets.DEV_API_URL }}
```

### 9.5 监控和日志最佳实践

#### 监控配置
```yaml
# 1. 应用指标
metrics:
  - name: http_requests_total
    type: counter
    description: Total number of HTTP requests
  - name: http_request_duration_seconds
    type: histogram
    description: HTTP request duration in seconds
  - name: active_connections
    type: gauge
    description: Number of active connections

# 2. 自定义指标
- name: business_events_total
  type: counter
  labels: [event_type, status]
  description: Total number of business events
```

#### 日志配置
```yaml
# 1. 结构化日志
logging:
  format: json
  level: info
  fields:
    timestamp: "@timestamp"
    level: log.level
    message: message
    service: service.name
    trace_id: trace.id

# 2. 日志收集
fluentd:
  input:
    - type: tail
      path: /var/log/containers/*.log
  output:
    - type: elasticsearch
      host: elasticsearch.logging.svc.cluster.local
      port: 9200
```

### 9.6 故障恢复最佳实践

#### 备份策略
```bash
# 1. 配置备份
kubectl get configmaps --all-namespaces -o yaml > backup-configmaps.yaml
kubectl get secrets --all-namespaces -o yaml > backup-secrets.yaml

# 2. 应用备份
kubectl get deployments --all-namespaces -o yaml > backup-deployments.yaml
kubectl get services --all-namespaces -o yaml > backup-services.yaml

# 3. 定期备份脚本
#!/bin/bash
BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/all-resources.yaml"
```

#### 恢复流程
```bash
# 1. 快速恢复
kubectl apply -f backup-deployments.yaml
kubectl apply -f backup-services.yaml

# 2. 滚动更新
kubectl rollout restart deployment/app-name --namespace=app

# 3. 紧急回滚
kubectl rollout undo deployment/app-name --namespace=app
```

### 9.7 性能优化最佳实践

#### 应用优化
```go
// 1. 连接池配置
db.SetMaxOpenConns(25)
db.SetMaxIdleConns(5)
db.SetConnMaxLifetime(5 * time.Minute)

// 2. 缓存策略
cache := redis.NewClient(&redis.Options{
    Addr:     "redis:6379",
    Password: "",
    DB:       0,
})

// 3. 并发控制
semaphore := make(chan struct{}, 10) // 限制并发数
```

#### 基础设施优化
```yaml
# 1. 节点亲和性
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-type
          operator: In
          values: ["application"]

# 2. 本地存储
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 10Gi
    storageClassName: ssd
```

### 9.8 安全最佳实践

#### 镜像安全
```bash
# 1. 镜像扫描
trivy image myapp:latest

# 2. 基础镜像更新
docker pull alpine:latest
docker build --no-cache -t myapp:latest .

# 3. 签名验证
cosign verify myapp:latest
```

#### 网络安全
```yaml
# 1. 服务网格
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp
spec:
  host: myapp.default.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL

# 2. 入口控制
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

---

## 10. 扩展与优化

### 10.1 高可用架构

#### 多节点集群
```yaml
# cluster-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
metadata:
  name: config
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "load-balancer:6443"
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "10.244.0.0/16"
etcd:
  external:
    endpoints:
    - "https://etcd1:2379"
    - "https://etcd2:2379"
    - "https://etcd3:2379"
```

#### 负载均衡配置
```yaml
# metalb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
```

### 10.2 服务网格集成

#### Istio 配置
```yaml
# istio-gateway.yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: myapp-gateway
  namespace: app
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp-vs
  namespace: app
spec:
  hosts:
  - "*"
  gateways:
  - myapp-gateway
  http:
  - match:
    - uri:
        prefix: /first-app
    route:
    - destination:
        host: app-first-app-develop
        port:
          number: 18080
```

#### 流量管理
```yaml
# traffic-splitting.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp-split
spec:
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: myapp-v1
        weight: 80
    - destination:
        host: myapp-v2
        weight: 20
```

### 10.3 监控扩展

#### Prometheus 配置
```yaml
# prometheus-values.yaml
server:
  retention: 15d
  persistentVolume:
    enabled: true
    size: 50Gi
  extraArgs:
    storage.tsdb.retention.time: 15d
    storage.tsdb.retention.size: 50GB

alertmanager:
  enabled: true
  persistentVolume:
    enabled: true
    size: 2Gi

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
```

#### Grafana Dashboard
```json
{
  "dashboard": {
    "title": "Application Performance",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{ method }} {{ status }}"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "singlestat",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m]) / rate(http_requests_total[5m])",
            "legendFormat": "Error Rate"
          }
        ]
      }
    ]
  }
}
```

### 10.4 日志聚合

#### ELK Stack 配置
```yaml
# elasticsearch-values.yaml
elasticsearch:
  replicas: 3
  minimumMasterNodes: 2
  volumeClaimTemplate:
    accessModes: [ "ReadWriteOnce" ]
    resources:
      requests:
        storage: 30Gi

kibana:
  replicas: 1
  service:
    type: LoadBalancer
    port: 5601

logstash:
  replicas: 2
  volumeClaimTemplate:
    accessModes: [ "ReadWriteOnce" ]
    resources:
      requests:
        storage: 10Gi
```

#### Filebeat 配置
```yaml
# filebeat-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
data:
  filebeat.yml: |
    filebeat.inputs:
    - type: container
      paths:
        - /var/log/containers/*.log
      processors:
        - add_kubernetes_metadata:
            host: ${NODE_NAME}
            matchers:
            - logs_path:
                logs_path: "/var/log/containers/"

    output.elasticsearch:
      hosts: ["elasticsearch:9200"]
      index: "filebeat-%{+yyyy.MM.dd}"

    logging.level: info
    logging.to_files: true
    logging.files:
      path: /var/log/filebeat
      name: filebeat
      keepfiles: 7
      permissions: 0644
```

### 10.5 自动化运维

#### 自动扩缩容
```yaml
# hpa-config.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "100"
```

#### 自动故障恢复
```yaml
# pod-disruption-budget.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
---
apiVersion: v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb-percent
spec:
  minAvailable: 50%
  selector:
    matchLabels:
      app: myapp
```

### 10.6 安全增强

#### Pod 安全策略
```yaml
# pod-security-policy.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: myapp-psp
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

#### 网络安全
```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: myapp-netpol
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

### 10.7 成本优化

#### 资源优化
```yaml
# resource-optimization.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: myapp-limits
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    type: Container
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: myapp-quota
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    count/pods: 10
```

#### 节点优化
```yaml
# node-optimization.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubelet-config
data:
  kubelet: |
    maxPods: 110
    podPidsLimit: 2048
    cpuManagerPolicy: static
    cpuManagerReconcilePeriod: 10s
    topologyManagerPolicy: best-effort
```

### 10.8 多云部署

#### 多集群管理
```yaml
# cluster-registry.yaml
apiVersion: clusterregistry.k8s.io/v1alpha1
kind: Cluster
metadata:
  name: cluster-east
  labels:
    region: east
    environment: production
---
apiVersion: clusterregistry.k8s.io/v1alpha1
kind: Cluster
metadata:
  name: cluster-west
  labels:
    region: west
    environment: production
```

#### 联邦配置
```yaml
# federation-config.yaml
apiVersion: core.kubefed.io/v1beta1
kind: KubeFedCluster
metadata:
  name: cluster-east
spec:
  apiEndpoint: https://cluster-east.example.com
  caBundle: "LS0tLS1CRUdJTi..."
  secretRef:
    name: cluster-east-secret
---
apiVersion: core.kubefed.io/v1beta1
kind: KubeFedCluster
metadata:
  name: cluster-west
spec:
  apiEndpoint: https://cluster-west.example.com
  caBundle: "LS0tLS1CRUdJTi..."
  secretRef:
    name: cluster-west-secret
```

---

## 总结

本教程完整介绍了基于 Kubernetes + GitHub Actions + Traefik 的微服务 CI/CD 实践方案，涵盖了从基础环境搭建到高级功能扩展的各个方面。

### 核心价值

1. **自动化**: 通过分支命名规范实现全自动部署，减少人工干预
2. **标准化**: 统一的配置管理和部署流程，提高开发效率
3. **可靠性**: 完善的健康检查和监控体系，确保系统稳定
4. **可扩展**: 模块化设计，支持快速扩展新服务和环境
5. **安全性**: 多层安全防护，保障生产环境安全

### 关键特性

- ✅ 多环境支持（开发、预发布、生产）
- ✅ 自动化分支解析和部署
- ✅ 容器化构建和部署
- ✅ 健康检查和自动恢复
- ✅ 监控和日志聚合
- ✅ 性能优化和成本控制
- ✅ 安全防护和合规管理

### 适用场景

- 微服务架构项目
- 中小型团队快速迭代
- 开发效率提升需求
- 系统可靠性要求高
- 需要标准化部署流程

通过本教程的实践，您可以构建一个高效、可靠、可扩展的微服务 CI/CD 平台，为业务快速发展提供强有力的技术支撑。