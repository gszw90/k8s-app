# Use Node.js runtime as base image
FROM node:18-alpine AS base

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create app directory
WORKDIR /app

# Set environment variables
ENV NODE_ENV=production

# Copy package files
COPY frontend/first_app/package*.json ./

# Install dependencies
RUN npm install --only=production && npm cache clean --force

# Stage 2: Build stage with configuration
FROM node:18-alpine AS builder

# Install dumb-init
RUN apk add --no-cache dumb-init

# Create app directory
WORKDIR /app

# Copy application files
COPY frontend/first_app/ ./

# Copy configuration files (build-time injection)
ARG CONFIG_ENV=develop
COPY frontend/first_app/config/config-${CONFIG_ENV}.json ./config/config.json

# Set proper permissions
RUN addgroup -g 1001 -S nodegroup && \
    adduser -u 1001 -S nodeuser -G nodegroup && \
    chown -R nodeuser:nodegroup /app

# Create non-root user
USER nodeuser

# Switch back to base stage
FROM base

# Copy built application from builder
COPY --from=builder --chown=nodeuser:nodegroup /app .

# Set environment for configuration path
ENV CONFIG_PATH=/app/config/config.json

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })" || exit 1

# Start the application with dumb-init
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/app.js"]