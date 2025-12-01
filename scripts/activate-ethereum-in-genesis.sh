#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENESIS_FILE="$PROJECT_ROOT/chaindata/axelar/config/genesis.json"

echo "🔧 激活 Ethereum 链并设置 Gateway..."
echo "--------------------------------"

# CREATE2 确定性 Gateway 地址
GATEWAY_ADDRESS="0x4BD9051a87E8d731E452eD84D22AA6E33b608E25"
echo "📋 Gateway 地址: $GATEWAY_ADDRESS"

# 备份 genesis
cp "$GENESIS_FILE" "$GENESIS_FILE.backup-eth"

# 1. 设置 Ethereum 链的 Gateway 地址
echo "🔨 设置 Ethereum Gateway 地址..."

# 直接使用字节数组 (0x4BD9051a87E8d731E452eD84D22AA6E33b608E25)
GATEWAY_BYTES="[75,217,5,26,135,232,215,49,228,82,237,132,210,42,166,227,59,96,142,37]"

jq --argjson gateway_bytes "$GATEWAY_BYTES" '
  .app_state.evm.chains[0].gateway.address = $gateway_bytes
' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

echo "   ✅ 已设置 Gateway 地址"

# 2. 激活 Ethereum 链
echo "🔨 激活 Ethereum 链..."

# 查找 Ethereum 在 chain_states 中的索引 (应该是 0，对应 Axelarnet)
# 实际上需要找到 Ethereum 的 chain_state，但 genesis 中可能还没有，需要添加

# 检查是否已有 Ethereum 的 chain_state
HAS_ETH_STATE=$(jq '.app_state.nexus.chain_states | map(.chain.name == "Ethereum") | any' "$GENESIS_FILE")

if [ "$HAS_ETH_STATE" == "true" ]; then
  echo "   Ethereum chain_state 已存在，设置为 activated"
  # 找到索引并设置 activated = true
  jq '(.app_state.nexus.chain_states[] | select(.chain.name == "Ethereum")).activated = true' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"
else
  echo "   添加 Ethereum chain_state 并激活"
  jq '.app_state.nexus.chain_states += [{
    "chain": {
      "name": "Ethereum",
      "native_asset_deprecated": "",
      "supports_foreign_assets": true,
      "key_type": "KEY_TYPE_MULTISIG",
      "module": "evm"
    },
    "activated": true,
    "assets": [],
    "maintainer_states": []
  }]' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"
fi

echo "   ✅ Ethereum 已激活"

echo ""
echo "✅ Ethereum 配置完成！"
echo ""
echo "📊 配置摘要:"
echo "   - Chain: Ethereum"
echo "   - Gateway: $GATEWAY_ADDRESS"
echo "   - Status: Activated"
