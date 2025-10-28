# GitHub Runner + kubectl 测试验证

## 测试目标
验证新部署的GitHub ARC Runner是否可以正常工作，特别是kubectl功能。

## 测试内容
1. GitHub Actions workflow执行
2. kubectl基本操作
3. Docker构建功能
4. K8s集群访问权限

## 测试时间
2025-10-28

## 预期结果
- ✅ GitHub Actions成功执行
- ✅ kubectl可以正常操作集群
- ✅ Runner保持稳定运行状态

## 实施方案
- 使用GitHub App认证的ARC Runner
- 共享kubectl二进制文件
- in-cluster K8s连接配置