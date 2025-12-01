#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENESIS_FILE="$PROJECT_ROOT/chaindata/axelar/config/genesis.json"

echo "🔧 配置 Genesis 文件..."
echo "--------------------------------"

# 检查 genesis 文件是否存在
if [ ! -f "$GENESIS_FILE" ]; then
  echo "❌ Genesis 文件不存在: $GENESIS_FILE"
  exit 1
fi

# 获取 validator 地址
VALIDATOR_ADDR=$(cd "$PROJECT_ROOT" && ./bin/axelard keys show validator --home chaindata/axelar --keyring-backend test --address 2>/dev/null || echo "")

if [ -z "$VALIDATOR_ADDR" ]; then
  echo "❌ 无法获取 validator 地址"
  exit 1
fi

echo "📋 Validator 地址: $VALIDATOR_ADDR"

# 备份原始 genesis
cp "$GENESIS_FILE" "$GENESIS_FILE.backup"
echo "✅ 已备份原始 genesis"

# 使用 jq 修改 genesis
echo "🔨 修改 genesis 配置..."

# 1. 缩短治理投票周期（方便测试）
jq '
  .app_state.gov.params.voting_period = "10s" |
  .app_state.gov.params.max_deposit_period = "10s"
' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

echo "   ✅ 已缩短投票周期为 10 秒"

echo ""
echo "✅ Genesis 配置完成！"
echo ""
echo "📊 配置摘要:"
echo "   - 投票周期: 10s"
echo "   - EVM 链: Ethereum, Polygon (将在下一步添加)"
echo ""
echo "💡 注意: Polygon 链将通过 add-polygon-to-genesis.sh 添加"
