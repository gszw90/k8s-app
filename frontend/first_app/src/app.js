// src/app.js
const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');

// 读取配置文件
function loadConfig() {
  const configPath = process.env.CONFIG_PATH || './config/config.json';

  try {
    const configFile = fs.readFileSync(configPath, 'utf8');
    return JSON.parse(configFile);
  } catch (error) {
    console.error('Error loading config:', error);
    return {
      name: 'web_app',
      mode: 'develop',
      version: '1.0.0',
      port: 3000
    };
  }
}

const config = loadConfig();

const server = http.createServer((req, res) => {
  // 健康检查端点
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      config: config
    }));
    return;
  }

  const hostname = os.hostname();

  const response = {
    message: 'Hello from Local K8s CI/CD!',
    app: config.name,
    mode: config.mode,
    version: config.version,
    hostname: hostname,
    timestamp: new Date().toISOString(),
    path: req.url
  };

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(response, null, 2));
});

const port = config.port || process.env.PORT || 3000;
server.listen(port, '0.0.0.0', () => {
  console.log(`Server running at http://0.0.0.0:${port}/`);
  console.log(`App: ${config.name}, Mode: ${config.mode}, Version: ${config.version}`);
});