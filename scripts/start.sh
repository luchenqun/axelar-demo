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

echo "🚀 启动两个 Reth 节点..."
echo "--------------------------------"

# 创建 chaindata 目录（如果不存在）
mkdir -p chaindata/chain-a chaindata/chain-b

# 启动 docker-compose
$DOCKER_COMPOSE up -d

# 等待节点启动
echo "⏳ 等待节点启动..."
sleep 1

# 检查节点状态
echo "📊 节点状态:"
$DOCKER_COMPOSE ps

echo ""
echo "✅ 节点已启动！"
echo "   Chain A: http://localhost:8545"
echo "   Chain B: http://localhost:7545"
