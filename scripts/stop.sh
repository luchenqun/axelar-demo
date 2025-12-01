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

# 停止 Reth 节点
echo "1️⃣  停止 Reth 节点 (Docker)..."
$DOCKER_COMPOSE down

# 停止本地进程
echo "2️⃣  停止本地进程 (Axelard & Tofnd)..."
pkill -f "bin/axelard"
pkill -f "bin/tofnd"

# 等待进程退出
sleep 2

echo ""
echo "✅ 所有服务已停止！"
