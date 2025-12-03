#!/bin/bash

# 检测 docker compose 命令
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
  DOCKER_COMPOSE="docker compose"
else
  echo "❌ 错误: 未找到 docker-compose 或 docker compose 命令"
  exit 1
fi

echo "🛑 停止服务..."
echo "--------------------------------"

# 停止 Hardhat 节点
echo "1️⃣  停止 Hardhat 节点..."
# 查找并停止 npx hardhat node 进程
pkill -f "hardhat node"

# 停止 Docker (如果有残留)
echo "2️⃣  清理 Docker 容器 (如果有)..."
$DOCKER_COMPOSE down 2> /dev/null

# 停止本地进程
echo "3️⃣  停止 Axelar & Tofnd..."
pkill -f "bin/axelard"
pkill -f "bin/tofnd"
pkill -f "vald-start"

# 等待进程退出
sleep 1

echo ""
echo "✅ 所有服务已停止！"
