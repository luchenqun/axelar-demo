#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENESIS_FILE="$PROJECT_ROOT/chaindata/axelar/config/genesis.json"

echo "🔧 配置验证者为链的 Maintainer..."
echo "--------------------------------"

# 获取 validator 地址（需要验证者格式：axelarvaloper...）
VALIDATOR_ADDR=$(cd "$PROJECT_ROOT" && ./bin/axelard keys show validator --home chaindata/axelar --keyring-backend test --bech val --address 2>/dev/null || echo "")

if [ -z "$VALIDATOR_ADDR" ]; then
  echo "❌ 无法获取 validator 地址"
  exit 1
fi

echo "📋 Validator 地址: $VALIDATOR_ADDR"

# 备份 genesis
cp "$GENESIS_FILE" "$GENESIS_FILE.backup-maintainers"

# 为 Ethereum 链添加 maintainer
echo "🔨 为 Ethereum 添加 maintainer..."

# 找到 Ethereum 的 chain_state 索引
ETH_INDEX=$(jq '[.app_state.nexus.chain_states[].chain.name] | index("Ethereum")' "$GENESIS_FILE")

if [ "$ETH_INDEX" != "null" ]; then
  jq --argjson idx "$ETH_INDEX" \
     --arg addr "$VALIDATOR_ADDR" '
    .app_state.nexus.chain_states[$idx].maintainer_states = [{
      "address": $addr,
      "supported_chains": ["Ethereum"],
      "missing_votes": [],
      "incorrect_votes": [],
      "chain_names": ["Ethereum"]
    }]
  ' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

  echo "   ✅ Ethereum maintainer 已添加"
else
  echo "   ❌ 找不到 Ethereum chain_state"
fi

# 为 Polygon 链添加 maintainer
echo "🔨 为 Polygon 添加 maintainer..."

# 找到 Polygon 的 chain_state 索引
POLYGON_INDEX=$(jq '[.app_state.nexus.chain_states[].chain.name] | index("Polygon")' "$GENESIS_FILE")

if [ "$POLYGON_INDEX" != "null" ]; then
  jq --argjson idx "$POLYGON_INDEX" \
     --arg addr "$VALIDATOR_ADDR" '
    .app_state.nexus.chain_states[$idx].maintainer_states = [{
      "address": $addr,
      "supported_chains": ["Polygon"],
      "missing_votes": [],
      "incorrect_votes": [],
      "chain_names": ["Polygon"]
    }]
  ' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

  echo "   ✅ Polygon maintainer 已添加"
else
  echo "   ❌ 找不到 Polygon chain_state"
fi

echo ""
echo "✅ Maintainer 配置完成！"
echo ""
echo "📊 配置摘要:"
echo "   - Maintainer: $VALIDATOR_ADDR"
echo "   - Chains: Ethereum, Polygon"
echo ""
echo "💡 验证者现在可以参与链的投票确认"
