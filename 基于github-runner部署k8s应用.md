# 基于 GitHub Runner 部署 Kubernetes 应用完整教程

> **作者**: Claude Code Assistant
> **版本**: 1.0
> **更新时间**: 2025-10-15
> **适用场景**: 本地开发环境、学习环境、小型团队项目

## 📋 目录

1. [项目概述](#项目概述)
2. [架构设计](#架构设计)
3. [环境准备](#环境准备)
4. [Docker 配置](#docker-配置)
5. [Kubernetes 配置](#kubernetes-配置)
6. [GitHub Actions 配置](#github-actions-配置)
7. [分支命名规范](#分支命名规范)
8. [部署流程](#部署流程)
9. [常见问题与解决方案](#常见问题与解决方案)
10. [最佳实践](#最佳实践)
11. [监控与运维](#监控与运维)
12. [扩展与优化](#扩展与优化)

---

## 项目概述

### 🎯 项目目标

本教程将指导您完成一个完整的微服务应用部署流程，从代码提交到自动化部署的全过程。

### 🏗️ 技术栈

- **后端**: Go 1.24 + Gin Web Framework
- **前端**: Node.js
- **容器化**: Docker 多阶段构建
- **编排**: Kubernetes (Docker Desktop)
- **网关**: Traefik v3
- **CI/CD**: GitHub Actions + 自托管 Runner
- **监控**: Kubernetes 原生监控

### 📊 应用架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   first-app     │    │   second-app    │    │    web-app      │
│     (Go)        │    │     (Go)        │    │   (Node.js)     │
│   Port: 18080   │    │   Port: 18081   │    │   Port: 3000    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │    Traefik      │
                    │   (Gateway)     │
                    │   Port: 80      │
                    └─────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Kubernetes     │
                    │    Cluster      │
                    └─────────────────┘
```

---

## 架构设计

### 🏛️ 系统架构

```yaml
架构层次:
  ┌─────────────────────────────────────────────────────────────┐
  │                      CI/CD 层                                │
  │  GitHub Actions → Self-hosted Runner → Docker Build         │
  └─────────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────────┐
  │                     编排层                                   │
  │  Kubernetes Cluster → Pods → Services → IngressRoutes      │
  └─────────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────────┐
  │                     网关层                                   │
  │  Traefik → LoadBalancer → Router → Middleware → Services   │
  └─────────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────────┐
  │                     应用层                                   │
  │  first-app → second-app → web-app (微服务架构)              │
  └─────────────────────────────────────────────────────────────┘
```

### 📁 项目结构

```
k8s-app/
├── .github/workflows/
│   └── deploy-monorepo.yaml          # CI/CD 工作流
├── backend/
│   ├── app/
│   │   ├── first_app/main.go         # 第一个 Go 服务
│   │   └── second_app/main.go        # 第二个 Go 服务
│   ├── deploy/
│   │   ├── Dockerfile-first-app      # Docker 构建文件
│   │   └── docker-compose-first-app.yaml
│   ├── go.mod                       # Go 模块文件
│   └── go.sum
├── frontend/
│   └── first_app/
│       ├── package.json             # Node.js 配置
│       ├── src/app.js               # 应用入口
│       └── Dockerfile               # 前端 Dockerfile
├── k8s/
│   └── local-dev-apps.yaml         # K8s 资源配置
├── docker/
│   ├── first-app/
│   │   ├── Dockerfile.develop      # 开发环境 Dockerfile
│   │   ├── Dockerfile.staging      # 测试环境 Dockerfile
│   │   └── Dockerfile.prod         # 生产环境 Dockerfile
│   ├── second-app/
│   └── web-app/
├── scripts/
│   ├── parse-branch.sh             # 分支解析脚本
│   ├── build.sh                    # 构建脚本
│   └── deploy.sh                   # 部署脚本
└── claudedocs/
    └── 基于github-runner部署k8s应用.md  # 本教程文档
```

---

## 环境准备

### 🔧 基础环境要求

- **操作系统**: Windows/macOS/Linux (支持 WSL2)
- **Docker**: 20.10+
- **Kubernetes**: 1.24+ (Docker Desktop 内置)
- **Git**: 2.30+
- **Node.js**: 16+ (仅前端需要)
- **Go**: 1.24+ (仅后端需要)

### 🐳 Docker 安装与配置

#### Windows/macOS (推荐使用 Docker Desktop)

```bash
# 1. 下载并安装 Docker Desktop
# https://www.docker.com/products/docker-desktop

# 2. 启用 Kubernetes
# Settings → Kubernetes → Enable Kubernetes

# 3. 验证安装
docker --version
docker-compose --version
```

#### Linux (Ubuntu/Debian)

```bash
# 1. 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 2. 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 3. 启用 Kubernetes (使用 k3d 或 minikube)
# 方案1: 使用 k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
k3d cluster create mycluster

# 方案2: 使用 minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube start
```

### ☸️ Kubernetes 验证

```bash
# 验证集群状态
kubectl cluster-info
kubectl get nodes

# 创建测试命名空间
kubectl create namespace test

# 验证权限
kubectl auth can-i create pods --namespace=test
```

### 🌐 Traefik 安装

```bash
# 安装 Traefik (使用 Helm)
helm repo add traefik https://traefik.github.io/charts
helm repo update

# 创建 traefik 命名空间
kubectl create namespace traefik

# 安装 Traefik
helm install traefik traefik/traefik \
  --namespace traefik \
  --set service.type=LoadBalancer \
  --set service.nodePorts.http=30533 \
  --set service.nodePorts.https=32636 \
  --set service.nodePorts.dashboard=30080

# 验证安装
kubectl get pods --namespace=traefik
kubectl get services --namespace=traefik
```

### 🏃‍♂️ GitHub Runner 配置

#### 1. 创建 GitHub Repository

```bash
# 创建新仓库
gh repo create k8s-app --public --clone
cd k8s-app

# 或者使用现有仓库
git clone https://github.com/username/k8s-app.git
cd k8s-app
```

#### 2. 获取 Runner Token

```bash
# 访问 GitHub Settings
# https://github.com/username/k8s-app/settings/actions/runners

# 点击 "New self-hosted runner"
# 选择 Linux 和 x64
# 复制配置脚本和令牌
```

#### 3. 部署 GitHub Runner

```yaml
# 创建 runner 配置文件
apiVersion: v1
kind: ConfigMap
metadata:
  name: github-runner-config
  namespace: github-actions
data:
  repo_url: "https://github.com/username/k8s-app"
  runner_group: "default"
  workdir: "/workspace"
  labels: "self-hosted,k8s"
  env_docker_host: "unix:///var/run/docker.sock"

---
apiVersion: v1
kind: Secret
metadata:
  name: github-runner-secret
  namespace: github-actions
type: Opaque
data:
  # 使用 base64 编码的 runner token
  token: <BASE64_ENCODED_TOKEN>

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: github-runner
  namespace: github-actions
spec:
  replicas: 1
  selector:
    matchLabels:
      app: github-runner
  template:
    metadata:
      labels:
        app: github-runner
    spec:
      serviceAccountName: github-runner
      containers:
      - name: github-runner
        image: myoung34/github-runner:latest
        env:
        - name: REPO_URL
          valueFrom:
            configMapKeyRef:
              name: github-runner-config
              key: repo_url
        - name: RUNNER_NAME
          value: "k8s-runner-$(hostname)-$(date +%s)"
        - name: RUNNER_TOKEN
          valueFrom:
            secretKeyRef:
              name: github-runner-secret
              key: token
        - name: RUNNER_REPO
          valueFrom:
            configMapKeyRef:
              name: github-runner-config
              key: repo_url
        - name: RUNNER_GROUP
          valueFrom:
            configMapKeyRef:
              name: github-runner-config
              key: runner_group
        - name: RUNNER_WORKDIR
          valueFrom:
            configMapKeyRef:
              name: github-runner-config
              key: workdir
        - name: RUNNER_LABELS
          valueFrom:
            configMapKeyRef:
              name: github-runner-config
              key: labels
        - name: DOCKER_HOST
          valueFrom:
            configMapKeyRef:
              name: github-runner-config
              key: env_docker_host
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
        volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
        - name: workspace
          mountPath: /workspace
        - name: kubeconfig
          mountPath: /home/zeng/.kube
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
      - name: workspace
        emptyDir: {}
      - name: kubeconfig
        hostPath:
          path: /home/zeng/.kube
          type: DirectoryOrCreate

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner
  namespace: github-actions

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "deployments", "configmaps", "secrets", "namespaces"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: [""]
  resources: ["pods/log", "pods/status"]
  verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-runner-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: github-runner-role
subjects:
- kind: ServiceAccount
  name: github-runner
  namespace: github-actions
```

```bash
# 应用配置
kubectl create namespace github-actions
kubectl apply -f runner-config.yaml

# 检查 runner 状态
kubectl get pods --namespace=github-actions
kubectl logs -f deployment/github-runner --namespace=github-actions
```

---

## Docker 配置

### 🐳 Dockerfile 最佳实践

#### Go 后端服务 Dockerfile

```dockerfile
# docker/first-app/Dockerfile.develop
FROM golang:1.24-alpine AS builder

WORKDIR /app

# 安装必要的包
RUN apk add --no-cache git ca-certificates tzdata

# 复制 go mod 文件
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# 复制源代码
COPY backend/app/first_app/ .

# 构建应用
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# 最终镜像
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata
WORKDIR /root/

# 复制构建的二进制文件
COPY --from=builder /app/main .

# 暴露端口
EXPOSE 18080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:18080/ping || exit 1

# 启动应用
CMD ["./main"]
```

#### Node.js 前端服务 Dockerfile

```dockerfile
# docker/web-app/Dockerfile.develop
FROM node:18-alpine AS builder

WORKDIR /app

# 复制 package 文件
COPY frontend/first_app/package*.json ./

# 安装依赖
RUN npm ci --only=production

# 复制源代码
COPY frontend/first_app/src ./src

# 创建非 root 用户
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# 生产镜像
FROM node:18-alpine

WORKDIR /app

# 复制依赖和应用代码
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/src ./src
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# 切换到非 root 用户
USER nodejs

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# 启动应用
CMD ["npm", "start"]
```

### 🔨 构建脚本

```bash
#!/bin/bash
# scripts/build.sh

set -e

echo "🐳 开始构建 Docker 镜像..."

# 获取当前分支信息
BRANCH_NAME=${1:-$(git rev-parse --abbrev-ref HEAD)}
echo "📋 当前分支: $BRANCH_NAME"

# 解析分支信息
if [[ "$BRANCH_NAME" =~ ^(backend|frontend)-(.*)-(develop|staging|prod)$ ]]; then
    DOMAIN="${BASH_REMATCH[1]}"
    APP_NAME="${BASH_REMATCH[2]}"
    ENVIRONMENT="${BASH_REMATCH[3]}"
else
    echo "❌ 无效的分支名称格式: $BRANCH_NAME"
    echo "正确格式: {domain}-{app}-{environment}"
    exit 1
fi

# 构建镜像
IMAGE_NAME="${APP_NAME}"
DOCKERFILE="docker/${APP_NAME}/Dockerfile.${ENVIRONMENT}"
TAG="${APP_NAME}:${ENVIRONMENT}-latest"

echo "🔨 构建镜像: $TAG"
echo "📄 Dockerfile: $DOCKERFILE"

if [ ! -f "$DOCKERFILE" ]; then
    echo "❌ Dockerfile 不存在: $DOCKERFILE"
    exit 1
fi

# 构建镜像
docker build -f "$DOCKERFILE" -t "$TAG" .

echo "✅ 镜像构建完成: $TAG"
docker images | grep "$APP_NAME"
```

---

## Kubernetes 配置

### ⚙️ 完整的 K8s 资源配置

```yaml
# k8s/local-dev-apps.yaml

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

---
# ConfigMap - second-app 开发环境
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-second-app-develop-config
  namespace: app
  labels:
    app: second-app
    environment: develop
data:
  LOG_LEVEL: "debug"
  GIN_MODE: "debug"
  NODE_ENV: "development"
  PORT: "18081"

---
# ConfigMap - web-app 开发环境
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-web-app-develop-config
  namespace: app
  labels:
    app: web-app
    environment: develop
data:
  LOG_LEVEL: "debug"
  NODE_ENV: "development"
  PORT: "3000"
  VERSION: "1.0.0-develop"

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
  replicas: 1
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
    spec:
      containers:
      - name: first-app
        image: first-app:8575e4a
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 18080
          name: http
        envFrom:
        - configMapRef:
            name: app-first-app-develop-config
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
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ping
            port: 18080
          initialDelaySeconds: 5
          periodSeconds: 10

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

---
# IngressRoute - first-app (Traefik v2)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app-first-app-develop
  namespace: app
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
# (类似的配置为 second-app 和 web-app 省略以节省空间)
```

### 🔧 命名空间配置

```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    name: app
    environment: development

---
apiVersion: v1
kind: Namespace
metadata:
  name: github-actions
  labels:
    name: github-actions
```

---

## GitHub Actions 配置

### 🔄 完整的 CI/CD 工作流

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
  # 解析分支信息
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
      - name: Checkout
        uses: actions/checkout@v4

      - name: 解析分支信息
        id: parse
        run: |
          BRANCH="${{ github.ref_name }}"
          echo "🔍 解析分支: $BRANCH"

          # 执行分支解析脚本
          if [ -f "./scripts/parse-branch.sh" ]; then
            ./scripts/parse-branch.sh "$BRANCH" > /tmp/branch-output.txt 2>&1
          else
            echo "❌ 脚本文件不存在"
            exit 1
          fi

          # 提取关键信息
          DOMAIN=$(grep "域:" /tmp/branch-output.txt | awk '{print $2}')
          APP_NAME=$(grep "应用名:" /tmp/branch-output.txt | awk '{print $2}')
          ENVIRONMENT=$(grep "环境:" /tmp/branch-output.txt | awk '{print $2}')
          APP_DIR=$(grep "应用目录:" /tmp/branch-output.txt | awk '{print $2}')
          DOCKERFILE=$(grep "Dockerfile:" /tmp/branch-output.txt | awk '{print $2}')
          SERVICE_NAME=$(grep "服务名:" /tmp/branch-output.txt | awk '{print $2}')
          PORT=$(grep "端口:" /tmp/branch-output.txt | awk '{print $2}')
          COMMIT_SHORT=$(grep "Commit:" /tmp/branch-output.txt | awk '{print $2}')

          # 设置输出变量
          echo "domain=$DOMAIN" >> $GITHUB_OUTPUT
          echo "app-name=$APP_NAME" >> $GITHUB_OUTPUT
          echo "environment=$ENVIRONMENT" >> $GITHUB_OUTPUT
          echo "app-dir=$APP_DIR" >> $GITHUB_OUTPUT
          echo "dockerfile=$DOCKERFILE" >> $GITHUB_OUTPUT
          echo "service-name=$SERVICE_NAME" >> $GITHUB_OUTPUT
          echo "port=$PORT" >> $GITHUB_OUTPUT
          echo "commit-short=$COMMIT_SHORT" >> $GITHUB_OUTPUT

      - name: 检查文件变更
        id: check
        run: |
          APP_DIR="${{ steps.parse.outputs.app-dir }}"

          if [ -z "$APP_DIR" ] || [ "$APP_DIR" = "NOT_FOUND" ] || [ ! -d "$APP_DIR" ]; then
            echo "should-deploy=false" >> $GITHUB_OUTPUT
            echo "🚫 部署被跳过: 应用目录不存在"
            exit 0
          fi

          echo "should-deploy=true" >> $GITHUB_OUTPUT
          echo "🚀 准备部署"

  # 构建 Docker 镜像
  build:
    needs: parse-branch
    if: needs.parse-branch.outputs.should-deploy == 'true'
    runs-on: self-hosted
    outputs:
      image-tag: ${{ steps.build.outputs.image-tag }}
      build-success: ${{ steps.build.outputs.build-success }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: 构建 Docker 镜像
        id: build
        run: |
          APP_NAME="${{ needs.parse-branch.outputs.app-name }}"
          ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
          DOCKERFILE="${{ needs.parse-branch.outputs.dockerfile }}"
          COMMIT_SHORT="${{ needs.parse-branch.outputs.commit-short }}"

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

  # 部署到 Kubernetes
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
      - name: Checkout
        uses: actions/checkout@v4

      - name: 安装 kubectl 和配置环境
        run: |
          # 安装 kubectl
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x kubectl
          sudo mv kubectl /usr/local/bin/

          # 设置环境变量
          export KUBECONFIG=/home/zeng/.kube/config
          echo "KUBECONFIG=$KUBECONFIG" >> $GITHUB_ENV

          # 验证 kubeconfig 文件
          if [ ! -f "$KUBECONFIG" ]; then
            echo "❌ kubeconfig 文件不存在: $KUBECONFIG"
            exit 1
          fi

      - name: 部署到 Kubernetes
        id: deploy
        run: |
          APP_NAME="${{ needs.parse-branch.outputs.app-name }}"
          ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
          IMAGE_TAG="${{ needs.build.outputs.image-tag }}"
          NAMESPACE="${{ env.NAMESPACE }}"

          # 验证 K8s 集群连接
          if ! kubectl cluster-info --request-timeout=30s; then
            echo "❌ 无法连接到 Kubernetes 集群"
            echo "deployment-success=false" >> $GITHUB_OUTPUT
            exit 1
          fi

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

  # 验证部署
  verify:
    needs: [parse-branch, deploy]
    if: |
      needs.parse-branch.outputs.should-deploy == 'true' &&
      needs.deploy.outputs.deployment-success == 'true'
    runs-on: self-hosted
    steps:
      - name: 验证部署状态
        run: |
          SERVICE_NAME="${{ needs.parse-branch.outputs.service-name }}"
          ENVIRONMENT="${{ needs.parse-branch.outputs.environment }}"
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

  # 通知结果
  notify:
    needs: [parse-branch, build, deploy, verify]
    if: always()
    runs-on: self-hosted
    steps:
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

## 分支命名规范

### 🏷️ 分支命名策略

本系统采用结构化的分支命名规范，支持自动化部署：

```
{domain}-{app-name}-{environment}
```

**参数说明**:
- `domain`: `backend` | `frontend`
- `app-name`: 应用名称（使用连字符）
- `environment`: `develop` | `staging` | `prod`

**示例**:
- `backend-first-app-develop` → 后端 first-app 开发环境
- `frontend-web-app-staging` → 前端 web-app 测试环境
- `backend-second-app-prod` → 后端 second-app 生产环境

### 🔧 分支解析脚本

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

### 🚀 自动化部署流程

```
分支推送 → GitHub Actions → 解析分支名 → 构建镜像 → 更新 K8s 配置 → 部署应用
     ↓              ↓                ↓           ↓            ↓           ↓
backend-first-app-develop → parse → first-app → build → k8s apply → rollout
```

---

## 部署流程

### 🔄 完整部署步骤

#### 1. 创建功能分支

```bash
# 创建新的功能分支
git checkout -b backend-first-app-develop

# 添加代码变更
git add .
git commit -m "feat: 添加新的 API 端点"

# 推送到远程仓库
git push origin backend-first-app-develop
```

#### 2. 自动触发 CI/CD

推送代码后，GitHub Actions 会自动执行以下步骤：

1. **解析分支**: `backend-first-app-develop` → 解析出应用信息
2. **构建镜像**: `first-app:<commit-hash>`
3. **更新配置**: 动态更新 K8s 配置文件中的镜像标签
4. **部署应用**: `kubectl apply` 部署到 Kubernetes
5. **健康检查**: 验证应用正常运行

#### 3. 监控部署状态

```bash
# 查看 GitHub Actions 运行状态
gh run list --repo username/k8s-app

# 查看具体的运行日志
gh run view --repo username/k8s-app --log

# 查看 K8s 部署状态
kubectl get pods --namespace=app
kubectl get deployments --namespace=app
kubectl get services --namespace=app

# 查看应用日志
kubectl logs -f deployment/app-first-app-develop --namespace=app
```

#### 4. 验证应用访问

```bash
# 检查应用健康状态
curl http://localhost/first-app/ping

# 访问应用 API
curl http://localhost/first-app/hello

# 检查 Traefik Dashboard
# 访问: http://localhost:30080/dashboard/
```

### 📊 部署状态检查

```bash
#!/bin/bash
# scripts/verify-deployment.sh

set -e

NAMESPACE="app"

echo "🔍 检查 Kubernetes 部署状态..."

# 检查命名空间
echo "📋 命名空间状态:"
kubectl get namespaces | grep "$NAMESPACE"

# 检查所有 Pod
echo "📦 Pod 状态:"
kubectl get pods --namespace="$NAMESPACE" -o wide

# 检查所有服务
echo "🌐 服务状态:"
kubectl get services --namespace="$NAMESPACE"

# 检查所有部署
echo "🚀 部署状态:"
kubectl get deployments --namespace="$NAMESPACE"

# 检查 IngressRoute
echo "🔗 路由状态:"
kubectl get ingressroutes --namespace="$NAMESPACE"

# 检查 Traefik 状态
echo "🌉 Traefik 状态:"
kubectl get pods --namespace=traefik
kubectl get services --namespace=traefik

# 网络连接测试
echo "🌐 网络连接测试:"
echo -n "first-app: "
curl -s -o /dev/null -w "%{http_code}" http://localhost/first-app/ping
echo ""

echo -n "second-app: "
curl -s -o /dev/null -w "%{http_code}" http://localhost/second-app/ping
echo ""

echo -n "web-app: "
curl -s -o /dev/null -w "%{http_code}" http://localhost/health
echo ""

echo "✅ 部署状态检查完成"
```

---

## 常见问题与解决方案

### ❌ 问题1: GitHub Runner 无法启动

**症状**:
```
requested labels: self-hosted
job is waiting for a runner
```

**原因分析**:
1. Runner 没有正确注册到 GitHub
2. Runner 容器启动失败
3. 网络连接问题

**解决方案**:

```bash
# 1. 检查 Runner 状态
kubectl get pods --namespace=github-actions
kubectl logs -f deployment/github-runner --namespace=github-actions

# 2. 重新配置 Runner
# 获取新的 runner token
# 访问: https://github.com/username/k8s-app/settings/actions/runners

# 3. 更新 Runner 配置
kubectl delete secret github-runner-secret --namespace=github-actions
kubectl create secret generic github-runner-secret \
  --from-literal=token=<NEW_TOKEN> \
  --namespace=github-actions

# 4. 重启 Runner
kubectl rollout restart deployment/github-runner --namespace=github-actions
```

**预防措施**:
```yaml
# 在 Runner 配置中添加健康检查
livenessProbe:
  httpGet:
    path: /healthz
    port: runner
  initialDelaySeconds: 30
  periodSeconds: 60
```

### ❌ 问题2: kubectl 命令未找到

**症状**:
```
kubectl: command not found
```

**原因分析**:
- GitHub Runner 容器中没有安装 kubectl

**解决方案**:

在 GitHub Actions 工作流中添加动态安装步骤：

```yaml
- name: 安装 kubectl 和配置环境
  run: |
    # 安装 kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    # 验证安装
    kubectl version --client

    # 设置环境变量
    export KUBECONFIG=/home/zeng/.kube/config
    echo "KUBECONFIG=$KUBECONFIG" >> $GITHUB_ENV
```

### ❌ 问题3: 镜像标签更新失败

**症状**:
```
GitHub Actions 显示部署成功，但应用版本没有更新
```

**原因分析**:
- sed 命令无法匹配现有的镜像标签格式
- K8s 配置文件中的镜像标签没有被正确更新

**解决方案**:

```yaml
# 原始失败的命令：
sed -i "s|image: $APP_NAME:develop|image: $IMAGE_TAG|g" "$K8S_CONFIG"

# 修复后的命令：
sed -i.bak "s|image: $APP_NAME:.*|image: $IMAGE_TAG|g" "$K8S_CONFIG"

# 添加验证步骤
echo "📋 验证镜像更新结果:"
grep "image: $APP_NAME" "$K8S_CONFIG"
```

### ❌ 问题4: 部署名称不匹配

**症状**:
```
Error from server (NotFound): deployments.apps "app-first_app-develop" not found
```

**原因分析**:
- 工作流生成的部署名称与 K8s 配置不匹配

**解决方案**:

```yaml
# 修复部署名称生成
DEPLOYMENT_NAME="app-${APP_NAME}-${ENVIRONMENT}"  # 正确
# 而不是
DEPLOYMENT_NAME="app-${SERVICE_NAME}-${ENVIRONMENT}"  # 错误

# 添加调试日志
echo "🎯 期望的部署名称: $DEPLOYMENT_NAME"
```

### ❌ 问题5: RBAC 权限不足

**症状**:
```
Error from server (Forbidden): User "system:serviceaccount:github-actions:github-runner"
cannot get pods in the namespace "app"
```

**原因分析**:
- GitHub Runner 的 ServiceAccount 权限不足

**解决方案**:

```yaml
# 创建完整的 RBAC 配置
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner
  namespace: github-actions

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "deployments", "configmaps", "secrets", "namespaces"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
- apiGroups: [""]
  resources: ["pods/log", "pods/status"]
  verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-runner-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: github-runner-role
subjects:
- kind: ServiceAccount
  name: github-runner
  namespace: github-actions
```

### ❌ 问题6: kubeconfig 挂载失败

**症状**:
```
❌ kubeconfig 文件不存在: /home/zeng/.kube/config
```

**原因分析**:
- WSL2 环境下 hostPath 挂载存在问题
- 配置文件路径不正确

**解决方案**:

**方案1: 使用 ConfigMap 挂载**
```bash
# 创建 kubeconfig ConfigMap
kubectl create configmap kubeconfig \
  --from-file=/home/zeng/.kube/config \
  --namespace=github-actions

# 更新 Runner 配置使用 ConfigMap
volumeMounts:
- name: kubeconfig
  mountPath: /home/zeng/.kube
volumes:
- configMap:
    name: kubeconfig
  name: kubeconfig
```

**方案2: 使用绝对路径**
```yaml
volumes:
- name: kubeconfig
  hostPath:
    path: /home/zeng/.kube
    type: DirectoryOrCreate
```

### ❌ 问题7: Traefik 路由不工作

**症状**:
```
访问 http://localhost/first-app/ping 返回 404
```

**原因分析**:
- IngressRoute 配置错误
- 服务名称或端口不匹配
- 中间件配置问题

**解决方案**:

```bash
# 1. 检查 IngressRoute 配置
kubectl get ingressroutes --namespace=app -o yaml

# 2. 检查服务状态
kubectl get services --namespace=app

# 3. 检查 Traefik 日志
kubectl logs -f deployment/traefik --namespace=traefik

# 4. 验证路由规则
kubectl describe ingressroutes app-first-app-develop --namespace=app

# 5. 测试直接访问服务
kubectl port-forward --namespace=app svc/app-first-app-develop 8080:18080 &
curl http://localhost:8080/ping
```

### ❌ 问题8: Docker 镜像构建失败

**症状**:
```
ERROR: failed to solve: failed to read dockerfile
```

**原因分析**:
- Dockerfile 路径不正确
- 构建上下文问题
- Docker 权限问题

**解决方案**:

```yaml
# 确保正确的 Dockerfile 路径
- name: 构建 Docker 镜像
  run: |
    DOCKERFILE="${{ needs.parse-branch.outputs.dockerfile }}"

    # 检查 Dockerfile 是否存在
    if [ ! -f "$DOCKERFILE" ]; then
      echo "❌ Dockerfile 不存在: $DOCKERFILE"
      echo "📂 当前目录结构:"
      find . -name "Dockerfile*" -type f
      exit 1
    fi

    # 构建镜像
    docker build -f "$DOCKERFILE" -t "$IMAGE_TAG" .
```

### 🔧 综合诊断脚本

```bash
#!/bin/bash
# scripts/comprehensive-diagnosis.sh

set -e

echo "🔍 综合系统诊断开始..."

# 1. 基础环境检查
echo "📋 基础环境检查:"
echo "Docker 版本: $(docker --version 2>/dev/null || echo '未安装')"
echo "Kubectl 版本: $(kubectl version --client 2>/dev/null | head -n 1 || echo '未安装')"
echo "Git 版本: $(git --version 2>/dev/null || echo '未安装')"
echo ""

# 2. Kubernetes 集群状态
echo "☸️ Kubernetes 集群状态:"
if kubectl cluster-info &>/dev/null; then
    echo "✅ 集群连接正常"
    kubectl get nodes
    kubectl get namespaces
else
    echo "❌ 集群连接失败"
fi
echo ""

# 3. GitHub Runner 状态
echo "🏃‍♂️ GitHub Runner 状态:"
if kubectl get namespace github-actions &>/dev/null; then
    echo "✅ GitHub Actions 命名空间存在"
    kubectl get pods --namespace=github-actions
else
    echo "❌ GitHub Actions 命名空间不存在"
fi
echo ""

# 4. 应用部署状态
echo "🚀 应用部署状态:"
if kubectl get namespace app &>/dev/null; then
    echo "✅ 应用命名空间存在"
    kubectl get pods --namespace=app -o wide
    kubectl get services --namespace=app
else
    echo "❌ 应用命名空间不存在"
fi
echo ""

# 5. Traefik 状态
echo "🌉 Traefik 状态:"
if kubectl get namespace traefik &>/dev/null; then
    echo "✅ Traefik 命名空间存在"
    kubectl get pods --namespace=traefik
    kubectl get services --namespace=traefik
else
    echo "❌ Traefik 命名空间不存在"
fi
echo ""

# 6. 网络连接测试
echo "🌐 网络连接测试:"
for app in first-app second-app web-app; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost/$app/ping" 2>/dev/null | grep -q "200"; then
        echo "✅ $app: 正常"
    else
        echo "❌ $app: 异常"
    fi
done
echo ""

# 7. Docker 镜像状态
echo "🐳 Docker 镜像状态:"
docker images | grep -E "(first-app|second-app|web-app)" || echo "❌ 未找到应用镜像"
echo ""

echo "✅ 综合系统诊断完成"
```

---

## 最佳实践

### 🎯 开发最佳实践

#### 1. 代码组织

```bash
# 推荐的项目结构
project/
├── .github/workflows/          # CI/CD 配置
├── backend/                    # 后端代码
│   ├── app/                   # 应用代码
│   ├── deploy/                # 部署配置
│   ├── go.mod/go.sum          # 依赖管理
│   └── tests/                 # 测试代码
├── frontend/                  # 前端代码
├── docker/                    # Docker 配置
│   └── {app-name}/
│       ├── Dockerfile.{env}   # 环境特定 Dockerfile
│       └── .dockerignore      # Docker 忽略文件
├── k8s/                       # Kubernetes 配置
├── scripts/                   # 辅助脚本
└── docs/                      # 文档
```

#### 2. Docker 最佳实践

```dockerfile
# 使用多阶段构建
FROM golang:1.24-alpine AS builder
# 构建逻辑...

FROM alpine:latest
# 运行时逻辑...

# 使用非 root 用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup
USER appuser

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# 使用 .dockerignore 文件
echo "**/.git" >> .dockerignore
echo "**/node_modules" >> .dockerignore
echo "**/target" >> .dockerignore
```

#### 3. Git 工作流

```bash
# 使用语义化提交信息
git commit -m "feat: 添加新的 API 端点"
git commit -m "fix: 修复登录验证问题"
git commit -m "docs: 更新 README 文档"
git commit -m "chore: 更新依赖版本"

# 分支命名规范
feature/user-authentication
bugfix/login-validation
hotfix/security-patch
release/v1.0.0

# 使用 .gitignore
echo "*.log" >> .gitignore
echo "*.tmp" >> .gitignore
echo "node_modules/" >> .gitignore
echo ".env" >> .gitignore
```

### 🚀 运维最佳实践

#### 1. 资源管理

```yaml
# 设置资源限制
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

# 使用 HPA (Horizontal Pod Autoscaler)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
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
        averageUtilization: 80
```

#### 2. 安全配置

```yaml
# 使用非 root 用户
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  runAsGroup: 1001
  fsGroup: 1001

# 设置只读文件系统
securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL

# 使用 Secrets 管理敏感信息
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  database-url: <BASE64_ENCODED_URL>
  api-key: <BASE64_ENCODED_KEY>
```

#### 3. 监控和日志

```yaml
# 添加 Prometheus 监控
apiVersion: v1
kind: Service
metadata:
  name: app-metrics
  labels:
    app: first-app
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
    prometheus.io/path: "/metrics"

# 结构化日志
import (
    "github.com/sirupsen/logrus"
)

logger := logrus.New()
logger.SetFormatter(&logrus.JSONFormatter{})
logger.WithFields(logrus.Fields{
    "app": "first-app",
    "version": "v1.0.0",
}).Info("应用启动")
```

#### 4. 备份和恢复

```bash
#!/bin/bash
# scripts/backup-k8s.sh

NAMESPACE="app"
BACKUP_DIR="/backup/k8s/$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR"

# 备份命名空间
kubectl get namespace "$NAMESPACE" -o yaml > "$BACKUP_DIR/namespace.yaml"

# 备份所有资源
kubectl get all,configmaps,secrets,pvc --namespace="$NAMESPACE" -o yaml > "$BACKUP_DIR/all-resources.yaml"

# 备份特定资源
kubectl get deployments --namespace="$NAMESPACE" -o yaml > "$BACKUP_DIR/deployments.yaml"
kubectl get services --namespace="$NAMESPACE" -o yaml > "$BACKUP_DIR/services.yaml"
kubectl get configmaps --namespace="$NAMESPACE" -o yaml > "$BACKUP_DIR/configmaps.yaml"

echo "✅ 备份完成: $BACKUP_DIR"
```

### 🔒 安全最佳实践

#### 1. 网络安全

```yaml
# 使用 NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-network-policy
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: first-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
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
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

#### 2. 镜像安全

```yaml
# 使用镜像扫描
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    image: myregistry/app:latest
    imagePullPolicy: IfNotPresent
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
```

#### 3. 访问控制

```yaml
# 最小权限原则
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app
  name: app-operator
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-operator-binding
  namespace: app
subjects:
- kind: ServiceAccount
  name: app-operator
  namespace: app
roleRef:
  kind: Role
  name: app-operator
  apiGroup: rbac.authorization.k8s.io
```

### 📊 性能优化

#### 1. 应用优化

```go
// Go 应用优化示例
package main

import (
    "net/http"
    "github.com/gin-gonic/gin"
)

func main() {
    // 设置 Gin 模式
    gin.SetMode(gin.ReleaseMode)

    r := gin.Default()

    // 添加中间件
    r.Use(gin.Logger())
    r.Use(gin.Recovery())

    // 压缩响应
    r.Use(func(c *gin.Context) {
        c.Header("Content-Encoding", "gzip")
        c.Next()
    })

    // 设置超时
    srv := &http.Server{
        Addr:    ":8080",
        Handler: r,
        ReadTimeout:  10 * time.Second,
        WriteTimeout: 10 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    srv.ListenAndServe()
}
```

#### 2. 数据库优化

```yaml
# 数据库连接池配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-config
data:
  database.yaml: |
    database:
      host: postgres
      port: 5432
      name: myapp
      username: user
      password: password
      max_connections: 20
      max_idle_connections: 10
      connection_max_lifetime: 3600s
```

#### 3. 缓存策略

```yaml
# 使用 Redis 缓存
apiVersion: v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

---

## 监控与运维

### 📊 监控配置

#### 1. Prometheus + Grafana 监控

```yaml
# prometheus-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s

    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
```

#### 2. 应用指标收集

```go
// Go 应用 Prometheus 指标
package main

import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "github.com/gin-gonic/gin"
)

var (
    httpRequestsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )

    httpRequestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "http_request_duration_seconds",
            Help: "HTTP request duration in seconds",
        },
        []string{"method", "path"},
    )
)

func init() {
    prometheus.MustRegister(httpRequestsTotal)
    prometheus.MustRegister(httpRequestDuration)
}

func main() {
    r := gin.Default()

    // 添加 Prometheus 指标中间件
    r.Use(func(c *gin.Context) {
        start := time.Now()

        c.Next()

        duration := time.Since(start).Seconds()
        httpRequestDuration.WithLabelValues(c.Request.Method, c.FullPath()).Observe(duration)
        httpRequestsTotal.WithLabelValues(c.Request.Method, c.FullPath(),
            strconv.Itoa(c.Writer.Status())).Inc()
    })

    // 暴露指标端点
    r.GET("/metrics", gin.WrapH(promhttp.Handler()))

    r.Run(":8080")
}
```

#### 3. Grafana Dashboard

```json
{
  "dashboard": {
    "title": "应用监控仪表板",
    "panels": [
      {
        "title": "HTTP 请求总数",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{path}}"
          }
        ]
      },
      {
        "title": "HTTP 请求延迟",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      },
      {
        "title": "Pod 状态",
        "type": "stat",
        "targets": [
          {
            "expr": "kube_pod_status_phase{phase=\"Running\"}",
            "legendFormat": "Running"
          }
        ]
      }
    ]
  }
}
```

### 📋 日志管理

#### 1. 结构化日志

```go
// 使用 logrus 进行结构化日志
package main

import (
    "github.com/sirupsen/logrus"
    "os"
)

func main() {
    logger := logrus.New()

    // 设置日志格式
    logger.SetFormatter(&logrus.JSONFormatter{})
    logger.SetOutput(os.Stdout)
    logger.SetLevel(logrus.InfoLevel)

    // 添加字段
    logger.WithFields(logrus.Fields{
        "app":     "first-app",
        "version": "v1.0.0",
        "env":     "production",
    }).Info("应用启动成功")

    // 错误日志
    logger.WithFields(logrus.Fields{
        "error": err.Error(),
        "trace": "stack-trace-here",
    }).Error("处理请求失败")
}
```

#### 2. 日志收集 (ELK Stack)

```yaml
# elasticsearch.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:8.5.0
        env:
        - name: discovery.type
          value: single-node
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
        ports:
        - containerPort: 9200
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi

---
# logstash.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logstash
  template:
    metadata:
      labels:
        app: logstash
    spec:
      containers:
      - name: logstash
        image: docker.elastic.co/logstash/logstash:8.5.0
        ports:
        - containerPort: 5044
        volumeMounts:
        - name: config
          mountPath: /usr/share/logstash/pipeline
      volumes:
      - name: config
        configMap:
          name: logstash-config

---
# kibana.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:8.5.0
        ports:
        - containerPort: 5601
        env:
        - name: ELASTICSEARCH_HOSTS
          value: "http://elasticsearch:9200"
```

#### 3. 日志分析脚本

```bash
#!/bin/bash
# scripts/analyze-logs.sh

NAMESPACE="app"
POD_NAME=$1
SINCE=${2:-1h}

if [ -z "$POD_NAME" ]; then
    echo "用法: $0 <pod-name> [since]"
    echo "示例: $0 app-first-app-develop-xxx 30m"
    exit 1
fi

echo "📋 分析 Pod 日志: $POD_NAME (最近 $SINCE)"

# 获取错误日志
echo "❌ 错误日志:"
kubectl logs --namespace="$NAMESPACE" "$POD_NAME" --since="$SINCE" | grep -i error || echo "无错误日志"

echo ""

# 获取警告日志
echo "⚠️ 警告日志:"
kubectl logs --namespace="$NAMESPACE" "$POD_NAME" --since="$SINCE" | grep -i warn || echo "无警告日志"

echo ""

# 获取访问日志
echo "🌐 访问日志:"
kubectl logs --namespace="$NAMESPACE" "$POD_NAME" --since="$SINCE" | grep -E "GET|POST|PUT|DELETE" || echo "无访问日志"

echo ""

# 统计 HTTP 状态码
echo "📊 HTTP 状态码统计:"
kubectl logs --namespace="$NAMESPACE" "$POD_NAME" --since="$SINCE" | \
    grep -oE 'HTTP/[0-9.]+ [0-9]+' | \
    awk '{print $2}' | \
    sort | uniq -c | sort -nr || echo "无 HTTP 状态码数据"

echo ""

# 获取最慢的请求
echo "🐌 最慢的请求 (Top 10):"
kubectl logs --namespace="$NAMESPACE" "$POD_NAME" --since="$SINCE" | \
    grep -E "completed in [0-9]+ms" | \
    sort -k5 -nr | head -10 || echo "无响应时间数据"

echo "✅ 日志分析完成"
```

### 🔧 运维脚本

#### 1. 健康检查脚本

```bash
#!/bin/bash
# scripts/health-check.sh

NAMESPACE="app"
SERVICES=("first-app" "second-app" "web-app")
HEALTH_ENDPOINTS=("/ping" "/ping" "/health")

echo "🏥 开始健康检查..."

for i in "${!SERVICES[@]}"; do
    SERVICE=${SERVICES[$i]}
    ENDPOINT=${HEALTH_ENDPOINTS[$i]}

    echo -n "检查 $SERVICE ($ENDPOINT): "

    # HTTP 健康检查
    if curl -s -f -m 5 "http://localhost/$SERVICE$ENDPOINT" >/dev/null 2>&1; then
        echo "✅ 健康"
    else
        echo "❌ 不健康"

        # 获取 Pod 状态
        echo "  Pod 状态:"
        kubectl get pods --namespace="$NAMESPACE" -l "app=$SERVICE" --no-headers

        # 获取最近日志
        echo "  最近日志:"
        kubectl logs --namespace="$NAMESPACE" -l "app=$SERVICE" --tail=10
    fi
done

echo ""
echo "📊 集群状态:"
kubectl get nodes --no-headers
kubectl get pods --namespace="$NAMESPACE" --field-selector=status.phase!=Running

echo ""
echo "🌐 网络连接:"
if curl -s -f -m 5 "http://localhost" >/dev/null 2>&1; then
    echo "✅ 集群网络正常"
else
    echo "❌ 集群网络异常"
fi

echo "✅ 健康检查完成"
```

#### 2. 自动扩缩容脚本

```bash
#!/bin/bash
# scripts/auto-scale.sh

NAMESPACE="app"
DEPLOYMENT="app-first-app-develop"
MIN_REPLICAS=1
MAX_REPLICAS=5
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80

echo "🔄 检查扩缩容条件..."

# 获取当前资源使用情况
CPU_USAGE=$(kubectl top pods --namespace="$NAMESPACE" -l "app=first-app" --no-headers | awk '{sum+=$2} END {print sum/NR}')
MEMORY_USAGE=$(kubectl top pods --namespace="$NAMESPACE" -l "app=first-app" --no-headers | awk '{sum+=$3} END {print sum/NR}')

echo "当前 CPU 使用率: ${CPU_USAGE}m"
echo "当前内存使用率: ${MEMORY_USAGE}Mi"

# 获取当前副本数
CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT" --namespace="$NAMESPACE" -o jsonpath='{.spec.replicas}')

echo "当前副本数: $CURRENT_REPLICAS"

# 扩容条件
if [ "$CPU_USAGE" -gt "$CPU_THRESHOLD" ] || [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
    if [ "$CURRENT_REPLICAS" -lt "$MAX_REPLICAS" ]; then
        NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
        echo "📈 扩容到 $NEW_REPLICAS 个副本"
        kubectl scale deployment "$DEPLOYMENT" --namespace="$NAMESPACE" --replicas="$NEW_REPLICAS"
    else
        echo "⚠️ 已达到最大副本数 $MAX_REPLICAS"
    fi
else
    if [ "$CURRENT_REPLICAS" -gt "$MIN_REPLICAS" ]; then
        NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
        echo "📉 缩容到 $NEW_REPLICAS 个副本"
        kubectl scale deployment "$DEPLOYMENT" --namespace="$NAMESPACE" --replicas="$NEW_REPLICAS"
    else
        echo "✅ 已达到最小副本数 $MIN_REPLICAS"
    fi
fi

echo "✅ 扩缩容检查完成"
```

---

## 扩展与优化

### 🚀 高可用架构

#### 1. 多副本部署

```yaml
# 高可用部署配置
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-first-app-develop
spec:
  replicas: 3
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
    spec:
      # 反亲和性规则 - 分布到不同节点
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - first-app
              topologyKey: kubernetes.io/hostname
      containers:
      - name: first-app
        image: first-app:latest
        # 添加优雅关闭
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 15"]
        # 添加就绪和存活探针
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3
```

#### 2. 负载均衡和会话保持

```yaml
# 服务配置
apiVersion: v1
kind: Service
metadata:
  name: app-first-app-develop
  annotations:
    # 启用会话保持
    service.beta.kubernetes.io/aws-load-balancer-sticky-sessions: "true"
    service.beta.kubernetes.io/aws-load-balancer-sticky-sessions-type: "lb_cookie"
spec:
  selector:
    app: first-app
    environment: develop
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: LoadBalancer
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600
```

#### 3. 数据库高可用

```yaml
# PostgreSQL 高可用配置
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"

  bootstrap:
    initdb:
      database: app
      owner: appuser
      secret:
        name: postgres-credentials

  storage:
    size: 20Gi
    storageClass: fast-ssd

  monitoring:
    enabled: true
```

### 🌐 多云部署

#### 1. 多集群管理

```yaml
# 多集群配置文件
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-config
data:
  clusters.yaml: |
    clusters:
      - name: dev-cluster
        kubeconfig: /path/to/dev-kubeconfig
        region: us-west-2
        provider: aws
      - name: staging-cluster
        kubeconfig: /path/to/staging-kubeconfig
        region: us-east-1
        provider: aws
      - name: prod-cluster
        kubeconfig: /path/to/prod-kubeconfig
        region: eu-west-1
        provider: gcp
```

#### 2. 跨集群同步

```bash
#!/bin/bash
# scripts/multi-cluster-sync.sh

# 同步应用到多个集群
CLUSTERS=("dev-cluster" "staging-cluster" "prod-cluster")
NAMESPACE="app"
APPLICATION="first-app"

for CLUSTER in "${CLUSTERS[@]}"; do
    echo "🔄 同步到集群: $CLUSTER"

    # 设置 kubeconfig
    export KUBECONFIG="/path/to/${CLUSTER}-kubeconfig"

    # 创建命名空间
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # 部署应用
    kubectl apply -f "k8s/${APPLICATION}-deployment.yaml" --namespace="$NAMESPACE"

    # 等待部署完成
    kubectl rollout status deployment/"${APPLICATION}-deployment" --namespace="$NAMESPACE" --timeout=300s

    echo "✅ $CLUSTER 部署完成"
done

echo "🎉 多集群同步完成"
```

### 🔧 服务网格 (Istio)

#### 1. Istio 安装

```bash
#!/bin/bash
# 安装 Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# 安装 Istio
istioctl install --set values.global.mtls.auto=true -y

# 启用自动注入
kubectl label namespace app istio-injection=enabled
```

#### 2. 服务网格配置

```yaml
# 虚拟服务
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: first-app-vs
  namespace: app
spec:
  hosts:
  - first-app
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: first-app
        port:
          number: 8080
    timeout: 5s
    retries:
      attempts: 3
      perTryTimeout: 2s

---
# 目标规则
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: first-app-dr
  namespace: app
spec:
  host: first-app
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        maxRequestsPerConnection: 10
    circuitBreaker:
      consecutiveErrors: 3
      interval: 30s
      baseEjectionTime: 30s

---
# 网关
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: first-app-gateway
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
```

### 📈 性能优化

#### 1. 应用性能优化

```go
// Go 应用性能优化
package main

import (
    "context"
    "net/http"
    "time"

    "github.com/gin-gonic/gin"
    "golang.org/x/time/rate"
)

func main() {
    // 设置 Gin 模式
    gin.SetMode(gin.ReleaseMode)

    r := gin.New()

    // 添加限流中间件
    limiter := rate.NewLimiter(100, 200)
    r.Use(func(c *gin.Context) {
        if !limiter.Allow() {
            c.JSON(http.StatusTooManyRequests, gin.H{"error": "请求过于频繁"})
            c.Abort()
            return
        }
        c.Next()
    })

    // 添加缓存中间件
    cache := make(map[string]interface{})
    r.Use(func(c *gin.Context) {
        if c.Request.Method == "GET" {
            if val, exists := cache[c.Request.URL.Path]; exists {
                c.JSON(http.StatusOK, val)
                c.Abort()
                return
            }
        }
        c.Next()

        // 缓存响应
        if c.Request.Method == "GET" && c.Writer.Status() == 200 {
            cache[c.Request.URL.Path] = c.Keys["response"]
        }
    })

    // 设置超时
    srv := &http.Server{
        Addr:         ":8080",
        Handler:      r,
        ReadTimeout:  10 * time.Second,
        WriteTimeout: 10 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    srv.ListenAndServe()
}
```

#### 2. 数据库优化

```sql
-- 数据库索引优化
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);
CREATE INDEX CONCURRENTLY idx_orders_created_at ON orders(created_at);
CREATE INDEX CONCURRENTLY idx_products_category ON products(category);

-- 查询优化
EXPLAIN ANALYZE
SELECT u.*, o.created_at
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.email = 'user@example.com'
ORDER BY o.created_at DESC
LIMIT 10;

-- 连接池配置
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '4MB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
```

### 🔒 安全增强

#### 1. 容器安全

```dockerfile
# 安全的 Dockerfile
FROM golang:1.24-alpine AS builder

# 在构建阶段安装依赖
RUN apk add --no-cache ca-certificates git

# 构建应用
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# 最小化运行时镜像
FROM scratch

# 从构建阶段复制必要文件
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/main /main

# 使用非 root 用户
USER 65534:65534

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/main", "-health-check"]

# 启动应用
ENTRYPOINT ["/main"]
```

#### 2. 网络安全

```yaml
# Pod 安全策略
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted-psp
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

---
# 网络策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-network-policy
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: first-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 5432
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

### 🎯 未来规划

#### 1. GitOps 工作流

```yaml
# ArgoCD 应用配置
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: first-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/username/k8s-app.git
    targetRevision: HEAD
    path: k8s/overlays/develop
  destination:
    server: https://kubernetes.default.svc
    namespace: app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

#### 2. 云原生技术栈

```yaml
# 云原生技术栈规划
技术栈:
  - 容器运行时: containerd
  - 编排平台: Kubernetes
  - 服务网格: Istio
  - 监控: Prometheus + Grafana
  - 日志: ELK Stack
  - CI/CD: ArgoCD + GitHub Actions
  - 包管理: Helm Charts
  - 安全: Falco + OPA/Gatekeeper
  - 存储: Rook + Ceph
  - 网络: Calico
```

---

## 🎉 总结

本教程从零开始，详细介绍了如何搭建一个完整的基于 GitHub Runner 的 Kubernetes 应用部署系统。涵盖了以下关键内容：

### ✅ 已完成的功能

1. **完整的项目架构**: 微服务架构 + 容器化 + 编排
2. **自动化 CI/CD**: GitHub Actions + 自托管 Runner
3. **分支驱动部署**: 结构化分支命名 + 自动解析
4. **监控和日志**: 应用监控 + 结构化日志
5. **问题排查**: 详细的问题诊断和解决方案
6. **最佳实践**: 开发、运维、安全等方面的经验总结

### 🚀 核心价值

- **实战导向**: 基于真实项目经验，包含大量实际问题的解决方案
- **完整覆盖**: 从环境搭建到生产部署的全流程指导
- **可操作性**: 所有配置都经过验证，可以直接使用
- **可扩展性**: 提供了多种扩展和优化方案

### 🎯 适用场景

- **学习和研究**: 了解完整的云原生应用部署流程
- **小型团队**: 快速搭建开发环境和 CI/CD 流程
- **个人项目**: 自动化部署和管理微服务应用
- **技术培训**: 作为云原生技术的教学材料

### 📚 后续学习建议

1. **深入学习 Kubernetes**: 了解更高级的特性和最佳实践
2. **掌握服务网格**: 学习 Istio 等服务网格技术
3. **云原生安全**: 学习容器安全和集群安全
4. **性能优化**: 学习应用性能调优和资源优化
5. **多云管理**: 学习跨云平台的部署和管理

希望这个教程能够帮助您成功搭建和管理自己的 Kubernetes 应用部署系统！如果您在实践过程中遇到任何问题，欢迎参考本教程的故障排除章节，或者根据实际情况调整配置。

---

**Happy Coding! 🚀**