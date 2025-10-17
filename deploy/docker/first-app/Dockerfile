# Stage 1: Build stage
FROM golang:1.24-alpine AS builder

# 安装必要的工具
RUN apk add --no-cache git

# 设置工作目录
WORKDIR /app

# 复制go mod文件并下载依赖
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# 复制源代码
COPY backend/app/first_app/main.go ./

# 构建应用（静态编译）
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o first_app main.go

# Stage 2: Final stage with configuration
FROM alpine:latest AS final

# 安装CA证书（如果需要HTTPS请求）
RUN apk --no-cache add ca-certificates

# 创建应用目录
WORKDIR /app

# 复制构建的二进制文件
COPY --from=builder /app/first_app .

# 复制配置文件（构建时注入）
ARG CONFIG_ENV=develop
COPY backend/app/first_app/config/config-${CONFIG_ENV}.yaml ./config/config.yaml

# 创建非root用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# 更改文件所有权
RUN chown -R appuser:appgroup /app
USER appuser

# 暴露端口
EXPOSE 18080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:18080/ping || exit 1

# 启动应用（使用配置文件）
ENTRYPOINT ["./first_app", "-c", "config/config.yaml"]