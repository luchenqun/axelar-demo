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

echo "🔄 重置两个 Reth 节点..."
echo "--------------------------------"

# 停止容器
echo "1️⃣  停止容器..."
$DOCKER_COMPOSE down

# 删除 chaindata
echo "2️⃣  删除链数据..."
rm -rf chaindata/chain-a/* chaindata/chain-b/*

# 重新启动
echo "3️⃣  重新启动节点..."
$DOCKER_COMPOSE up -d

# 等待节点启动
echo "⏳ 等待节点启动..."
sleep 1

# 检查节点状态
echo "📊 节点状态:"
$DOCKER_COMPOSE ps

echo ""
echo "✅ 节点已重置并启动！"
echo "   Chain A: http://localhost:8545"
echo "   Chain B: http://localhost:7545"
