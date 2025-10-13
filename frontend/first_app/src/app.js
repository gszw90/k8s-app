// src/app.js
const http = require('http');
const os = require('os');

const server = http.createServer((req, res) => {
  const hostname = os.hostname();
  const version = process.env.VERSION || '1.0.0';
  
  const response = {
    message: 'Hello from Local K8s CI/CD!',
    version: version,
    hostname: hostname,
    timestamp: new Date().toISOString(),
    path: req.url
  };
  
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(response, null, 2));
});

// 健康检查端点
server.on('request', (req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }));
    return;
  }
});

const port = process.env.PORT || 3000;
server.listen(port, '0.0.0.0', () => {
  console.log(`Server running at http://0.0.0.0:${port}/`);
});