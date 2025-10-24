# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a local Kubernetes CI/CD learning project with a microservices architecture consisting of:
- **Backend**: Two Go services using Gin web framework (`first_app` on port 18080, `second_app` on port 18081)
- **Frontend**: A Node.js HTTP service (port 3000) that serves version and host information
- **Deployment**: Docker containerization with GitHub Actions for CI/CD

## Architecture

### Backend Structure (`/backend`)
```
backend/
├── app/
│   ├── first_app/main.go    # First service on :18080
│   └── second_app/main.go   # Second service on :18081
├── deploy/
│   ├── Dockerfile-first-app # Multi-stage Docker build
│   └── docker-compose-first-app.yaml
├── go.mod                   # Go 1.24.0, Gin dependencies
└── go.sum
```

### Frontend Structure (`/frontend/first_app`)
```
frontend/first_app/
├── package.json             # Basic Node.js with start/test scripts
├── src/app.js              # HTTP server with JSON responses
└── (no dependencies)
```

### Services
- **first_app** (Go): `/ping`, `/hello` endpoints
- **second_app** (Go): `/ping`, `/hello` endpoints
- **frontend** (Node.js): Root endpoint, `/health` check

## Development Commands

### Backend (Go)
```bash
# Run first app
cd backend/app/first_app && go run main.go

# Run second app
cd backend/app/second_app && go run main.go

# Build for container
cd backend && go build -o first_app app/first_app/main.go
```

### Frontend (Node.js)
```bash
cd frontend/first_app
npm start          # Start server (default port 3000)
npm run dev        # Same as start
npm test           # Placeholder test that always passes
```

### Docker Development
```bash
# Build and run first app container
cd backend/deploy
docker-compose -f docker-compose-first-app.yaml up --build

# The Dockerfile builds from ../ (backend root) and targets first_app/main.go
```

## CI/CD Pipeline

The project uses GitHub Actions with environment-specific branches:
- `develop-backend-first-app` → development environment
- `staging-backend-first-app` → staging environment
- `prod-backend-first-app` → production environment

The workflow (`.github/workflows/deploy-backend.yaml`) runs on self-hosted runners and sets environment variables based on the branch.

### GitHub Runner (K8s Self-Hosted)
- **Namespace**: `github-runners`
- **Deployment**: `github-runner-simple` with auto-healing capabilities
- **Auto-Restart**: K8s native self-healing ensures runner automatically recovers after cluster restart
- **Persistent Storage**: 5Gi PVC for runner state and Docker socket/lib mounting
- **Health Checks**: Liveness (60s delay) and Readiness (30s delay) probes
- **Repository**: Configured for `gszw90/k8s-app` repository

**K8s Auto-Restart Features:**
- ✅ Automatic pod recreation on failure
- ✅ Persistent configuration and data across restarts
- ✅ Health monitoring with automatic recovery
- ✅ Zero manual intervention required after K8s restart
- ✅ Runner automatically connects to GitHub when K8s cluster starts

**Runner Management:**
```bash
# Check runner status
kubectl get pods -n github-runners -l app=github-runner

# View runner logs
kubectl logs -f deployment/github-runner-simple -n github-runners

# Restart runner if needed
kubectl rollout restart deployment/github-runner-simple -n github-runners
```

## Key Development Notes

- Both Go apps are nearly identical with different port numbers and response messages
- The Dockerfile is specific to `first_app` - would need modification for `second_app`
- Frontend serves version info from `VERSION` environment variable
- No external database dependencies - all services are stateless
- Health check endpoint available on frontend at `/health`
- GitHub Runner has K8s native auto-healing - no manual restart needed after K8s reboot

## language-chat
使用中文来交流对话,文档也使用中文来写，代码中使用英文作为注释

## 命令执行
我的sudo密码是weiwei，一般正常的命令不需要使用sudo权限，只有明确提示权限不足时才使用sudo。

## 历史文档保存路径
历史文档保存在(./docs)目录下，以后得总结归纳文档都保存在这个目录下，命名规范为：时间_文档名.md
每次启动先读取这里的历史文档与总结文档，然后根据需要添加新的总结文档，更新CLUADE.md。

## 脚本文件
脚本文件保存在(./scripts)目录下，项目中用到的脚本都保存在该目录下。

## 任务/会话处理
每次一个任务或者一个会话完成后，总结当前任务或者会话，合并到CLUADE.md中，并保存到历史文档中，过程中产生的文件也需要合并与总结。

## GitHub Actions K8s连接问题 (2025-10-22)
**问题**: GitHub Actions自动部署在deploy阶段K8s连接失败
**状态**: ❌ **未解决** - 临时解决方案已准备
**根因**: GitHub Actions运行在隔离环境中，无法访问本地kubeconfig文件
**尝试方案**:
- 方案1: 加载/etc/profile (失败 - 非登录shell)
- 方案2: 多方法配置策略 (本地测试✅，GitHub Actions❌)
**临时解决方案**: 使用GitHub Actions Secrets存储kubeconfig (见 `docs/2025-10-22_temp-solution-kubeconfig-secret.md`)
**文档**:
- 详细记录: `docs/2025-10-22_github-actions-k8s-unresolved.md`
- 修复过程: `docs/2025-10-22_github-actions-k8s-fix.md`
- 临时方案: `docs/2025-10-22_temp-solution-kubeconfig-secret.md`

## 配置数据
- 在当前仓库安装的github app配置如下
```yaml
AppName: runner-ci-cd
AppId: 2168366
ClientId: Iv23lizdOiISiUHCD7of
InstationId: 91349326 
GithubAppPrivateKey: |
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAyqpY5aMjHgVXZD5ELl8nhIrK1tH7b95rjLAQVQaYnA1UnlCi
+7n6CbNvfkFgrvR012LyyJd+lTwi2D6ZkL5s1fhlAqnwrnLNBq9huZXjnCXKExY1
YUNsx7qfnsHd1gOBFm0OpurkWMVnnAS3VJEdUkIERoz/jgl7LHaptbl9ZVFhL9uF
KQlwBRfx15eWB6+Til9gq7pCKCaY2xejoHzpegRYgtrYMOy5wBLFcLXddvLMDdeN
y1xIrcXYWcYGRlADLyeoMJLJ/4NmCwlbTQ7/y80QnF63l8gPlbtHATHcg+Ef/8aF
C80OTDZ8bqbD/EExlQO23AB3zWf5ZPq52cE7+QIDAQABAoIBAGQfPiXMr5ewOdlr
LZHfLo27Z7QzLs24i1eIz7jBtnk52LkRy0MjQNS0EfvE3rfwSxzxZFIXDdE6UViV
rJYmjWwz9+sV+7KjQojv8g6Wb0kAHlHJoft4LPCLUTpEOoz1VDu5CwkJeGAmviYE
6nFb86lkteoI1GPeaTyxLux5Q+reJUQjg+ZQiU17n1dnYJzlumT9kcy4D9K/erek
+x++VjCuamYOtAPm/4TDh5X6qrFMlnPzTm1L1OJha2ZowE6giNNhSW1MW7OtUgEA
HLpdvKcw2fmKMzwoidwLHL5913EieAKecPOH80q7xIWc3jjmQU1BHgGhyylfj9bv
t6qAuwECgYEA6t6sz0dr80p8p+wuevWK0VuiY2HZYGIQ0qB0kapUj5OQR7+BMZak
PaibWi4DfS6bZcuoyWA6AdwBJ6/pFfxDzcbbeEuB0Gqqi40Rhvr4wqbkAk13UkSb
0H2bjOHmDkqYefPva94ZKQcT7bN+9CmakQ6/RrQYth7jlQFqWubiASECgYEA3OX3
o5QLqg0DKZKMOEzhgCWVF9ZmaJI6xEx+N9p0z5fvACGZWQgd916EXBdXbyPLMnrw
n9Yuwpdt3+iGC2wsxfoVSpdyTOE6IER39D6l7gloB9hg/TRms57phPWxjSiTy014
rZ0uoIfKC9iU63F83pDDqkXv5PPs92enwSx6Z9kCgYEAwYnEdPmxpsVWezlQA9qa
DXKpGaPj8Fxe6HF4HSByle1PExBncWlk5bouad1I2rqxKuzrpSU6J5YXDZETTR6W
8NZQu4vc6NU8u8n/C2971UqY0JztGkmW6/LVXv43CMfHZZbxT72wlfJTJainkKNH
zwiL7cMyKcDCYGLONSHUUoECgYBPw9a9QatIl3RJ4boyZkiTTn7c4bWPEyaXVYvK
PV8qyxEpefh2tsCjX4TqAB+5aTJpow0ammu+JpItZThqDYDJaHmhurgyXK3xkufB
0ZF3N/xRwOec5vwi5kIqmdGoSDu+ENZ/0p9QplfmGSoFLrDJaXrOFH0Arrglyk9A
KQB2WQKBgQCgTbnDNEL78cRy1ZSRQcGEXyIATrrAPYDp6axbHiHvfuAspzpGnQMu
weReRBR4VPglRFm2U293FYJrBSCoCDjE25NtMPAAWkEpDWOakWjzz2x4rGlVOrk9
92+OX2q2WPU97b7TXSy2zeCeeM5sK1DeWkJCy3DvWcNILTJbMCCqKA==
-----END RSA PRIVATE KEY-----

```