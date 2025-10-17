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

## Key Development Notes

- Both Go apps are nearly identical with different port numbers and response messages
- The Dockerfile is specific to `first_app` - would need modification for `second_app`
- Frontend serves version info from `VERSION` environment variable
- No external database dependencies - all services are stateless
- Health check endpoint available on frontend at `/health`

## language-chat
使用中文来交流对话，代码中使用英文作为注释

## 命令执行
我的sudo密码是weiwei，一般正常的命令不需要使用sudo权限，只有明确提示权限不足时才使用sudo。

## 历史文档保存路径
历史文档保存在(./docs)目录下，以后得总结归纳文档都保存在这个目录下，命名规范为：时间_文档名.md
每次启动先读取这里的历史文档与总结文档，然后根据需要添加新的总结文档，更新CLUADE.md。

## 脚本文件
脚本文件保存在(./scripts)目录下，项目中用到的脚本都保存在该目录下。