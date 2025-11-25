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

echo "🔄 重启两个 Reth 节点..."
echo "--------------------------------"

# 重启 docker-compose
$DOCKER_COMPOSE restart

# 等待节点启动
echo "⏳ 等待节点启动..."
sleep 1

# 检查节点状态
echo "📊 节点状态:"
$DOCKER_COMPOSE ps

echo ""
echo "✅ 节点已重启！"
echo "   Chain A: http://localhost:8545"
echo "   Chain B: http://localhost:7545"
