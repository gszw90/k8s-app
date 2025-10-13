# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dual-stack web application designed for learning Kubernetes and CI/CD concepts. The project consists of a Go backend and a Node.js frontend, both containerized for local Kubernetes deployment.

## Project Structure

```
├── backend/first_app/        # Go backend application
│   ├── main.go              # Main application entry point
│   └── go.mod              # Go module definition
├── frontend/first_app/      # Node.js frontend application
│   ├── src/app.js          # Main HTTP server with health check
│   └── package.json        # Node.js project configuration
└── .gitignore              # Git ignore rules
```

## Development Commands

### Backend (Go)
- Build: `cd backend/first_app && go build main.go`
- Run: `cd backend/first_app && go run main.go`
- Module management: `cd backend/first_app && go mod tidy`

### Frontend (Node.js)
- Install dependencies: `cd frontend/first_app && npm install`
- Start development server: `cd frontend/first_app && npm start`
- Run tests: `cd frontend/first_app && npm test`

## Architecture Details

### Backend (Go)
- Simple Go application that prints runtime information (OS and architecture)
- Uses Go 1.24.0
- Entry point: `backend/first_app/main.go:8`

### Frontend (Node.js)
- HTTP server with health check endpoint
- Returns JSON response with version, hostname, timestamp, and request path
- Health check endpoint at `/health`
- Listens on port 3000 by default (configurable via PORT environment variable)
- Entry point: `frontend/first_app/src/app.js:5`

## Environment Configuration

### Frontend Environment Variables
- `PORT`: Server port (default: 3000)
- `VERSION`: Application version (default: "1.0.0")

## Key Files

- `backend/first_app/main.go`: Backend application logic
- `frontend/first_app/src/app.js`: Frontend HTTP server and health check implementation
- `.gitignore`: Excludes IDE directories and Go modules