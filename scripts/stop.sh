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

echo "🛑 停止两个 Reth 节点..."
echo "--------------------------------"

# 停止 docker-compose
$DOCKER_COMPOSE down

echo ""
echo "✅ 节点已停止！"
