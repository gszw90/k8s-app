# 使用官方 Node.js 运行时作为基础镜像
FROM node:18-alpine

# 设置工作目录
WORKDIR /app

# 复制 package.json 和 package-lock.json（如果存在）
COPY package*.json ./

# 安装依赖
RUN npm install --production

# 创建非 root 用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# 复制应用源代码
COPY . .

# 如果应用文件在src目录中，复制到工作目录
RUN if [ -d "src" ]; then cp src/* . ; fi

# 更改文件所有者
RUN chown -R appuser:appgroup /app

# 切换到非 root 用户
USER appuser

# 暴露端口
EXPOSE 3000

# 设置环境变量
ENV NODE_ENV=production

# 运行应用
CMD ["npm", "start"]