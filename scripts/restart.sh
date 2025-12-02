#!/bin/bash

# 确保在项目根目录执行
if [ ! -d "scripts" ]; then
  echo "❌ 错误: 请在项目根目录下运行此脚本"
  exit 1
fi

echo "🔄 重启 Axelar 开发环境..."
echo "--------------------------------"

./scripts/stop.sh
sleep 2
./scripts/start.sh
