#!/bin/bash

# 确保在项目根目录执行
if [ ! -d "scripts" ]; then
    echo "❌ 错误: 请在项目根目录下运行此脚本"
    exit 1
fi

echo "🔄 重置 Axelar 开发环境 (Hardhat + Axelar + Tofnd)..."
echo "--------------------------------"

# 1. 停止所有服务
./scripts/stop.sh

# 2. 清理数据
echo "🧹 清理数据文件..."

# 清理 Reth 数据 (虽然不用了，但也清理一下以防万一)
echo "   清理链数据..."
rm -rf chaindata/chain-a/* chaindata/chain-b/*

# 清理 Axelar 和 Tofnd 数据
echo "   清理 Axelar 和 Tofnd 数据 (chaindata/)..."
rm -rf chaindata/axelar chaindata/tofnd chaindata/logs

# 如果之前的 data 目录存在，也一并清理
rm -rf data/

echo "✅ 数据清理完成"
echo ""

# 3. 重新启动
./scripts/start.sh
