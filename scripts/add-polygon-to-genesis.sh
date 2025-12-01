#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENESIS_FILE="$PROJECT_ROOT/chaindata/axelar/config/genesis.json"

echo "🔧 添加 Polygon 链到 Genesis..."
echo "--------------------------------"

# 检查 genesis 文件是否存在
if [ ! -f "$GENESIS_FILE" ]; then
  echo "❌ Genesis 文件不存在: $GENESIS_FILE"
  exit 1
fi

# 备份 genesis
cp "$GENESIS_FILE" "$GENESIS_FILE.backup.$(date +%s)"
echo "✅ 已备份 genesis"

# 读取 params-polygon.json
POLYGON_PARAMS=$(cat "$PROJECT_ROOT/src/params-polygon.json")

# 提取参数
CHAIN_NAME=$(echo "$POLYGON_PARAMS" | jq -r '.chain')
CONFIRMATION_HEIGHT=$(echo "$POLYGON_PARAMS" | jq -r '.confirmation_height')
NETWORK=$(echo "$POLYGON_PARAMS" | jq -r '.network')
TOKEN_CODE=$(echo "$POLYGON_PARAMS" | jq -r '.token_code')
BURNABLE=$(echo "$POLYGON_PARAMS" | jq -r '.burnable')
REVOTE_LOCKING=$(echo "$POLYGON_PARAMS" | jq -r '.revote_locking_period')
NETWORKS=$(echo "$POLYGON_PARAMS" | jq -c '.networks')
VOTING_THRESHOLD=$(echo "$POLYGON_PARAMS" | jq -c '.voting_threshold')
MIN_VOTER_COUNT=$(echo "$POLYGON_PARAMS" | jq -r '.min_voter_count')
COMMANDS_GAS_LIMIT=$(echo "$POLYGON_PARAMS" | jq -r '.commands_gas_limit')
VOTING_GRACE_PERIOD=$(echo "$POLYGON_PARAMS" | jq -r '.voting_grace_period')
END_BLOCKER_LIMIT=$(echo "$POLYGON_PARAMS" | jq -r '.end_blocker_limit')
TRANSFER_LIMIT=$(echo "$POLYGON_PARAMS" | jq -r '.transfer_limit')

echo "📋 参数: Chain=$CHAIN_NAME, Network=$NETWORK"

# 1. 添加到 evm.chains 数组
echo "🔨 添加到 app_state.evm.chains..."

jq --arg chain "$CHAIN_NAME" \
   --arg conf_height "$CONFIRMATION_HEIGHT" \
   --arg network "$NETWORK" \
   --arg token_code "$TOKEN_CODE" \
   --arg burnable "$BURNABLE" \
   --arg revote "$REVOTE_LOCKING" \
   --argjson networks "$NETWORKS" \
   --argjson voting_threshold "$VOTING_THRESHOLD" \
   --arg min_voter "$MIN_VOTER_COUNT" \
   --arg gas_limit "$COMMANDS_GAS_LIMIT" \
   --arg grace_period "$VOTING_GRACE_PERIOD" \
   --arg end_blocker "$END_BLOCKER_LIMIT" \
   --arg transfer_limit "$TRANSFER_LIMIT" '
  .app_state.evm.chains += [{
    "params": {
      "chain": $chain,
      "confirmation_height": $conf_height,
      "network": $network,
      "token_code": $token_code,
      "burnable": $burnable,
      "revote_locking_period": $revote,
      "networks": $networks,
      "voting_threshold": $voting_threshold,
      "min_voter_count": ($min_voter | tonumber),
      "commands_gas_limit": ($gas_limit | tonumber),
      "voting_grace_period": $grace_period,
      "end_blocker_limit": $end_blocker,
      "transfer_limit": $transfer_limit
    },
    "burner_infos": [],
    "command_queue": {
      "items": {}
    },
    "confirmed_deposits": [],
    "burned_deposits": [],
    "command_batches": [],
    "gateway": {
      "address": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
    },
    "tokens": [],
    "events": [],
    "confirmed_event_queue": {
      "items": {}
    },
    "legacy_confirmed_deposits": [],
    "legacy_burned_deposits": []
  }]
' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

echo "   ✅ 已添加到 evm.chains"

# 2. 设置 Gateway 地址（CREATE2 确定性地址）
GATEWAY_ADDRESS="0x4BD9051a87E8d731E452eD84D22AA6E33b608E25"
echo "🔨 设置 Gateway 地址: $GATEWAY_ADDRESS..."

# 直接使用字节数组 (0x4BD9051a87E8d731E452eD84D22AA6E33b608E25)
# 手动转换为十进制数组：75,217,5,26,135,232,215,49,228,82,237,132,210,42,166,227,59,96,142,37
GATEWAY_BYTES="[75,217,5,26,135,232,215,49,228,82,237,132,210,42,166,227,59,96,142,37]"

jq --argjson idx "$(jq '.app_state.evm.chains | length - 1' "$GENESIS_FILE")" \
   --argjson gateway_bytes "$GATEWAY_BYTES" '
  .app_state.evm.chains[$idx].gateway.address = $gateway_bytes
' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

echo "   ✅ 已设置 Gateway 地址"

# 3. 添加到 nexus.chains 数组
echo "🔨 添加到 app_state.nexus.chains..."

jq --arg chain "$CHAIN_NAME" '
  .app_state.nexus.chains += [{
    "name": $chain,
    "native_asset_deprecated": "",
    "supports_foreign_assets": true,
    "key_type": "KEY_TYPE_MULTISIG",
    "module": "evm"
  }]
' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

echo "   ✅ 已添加到 nexus.chains"

# 4. 添加到 nexus.chain_states 数组并激活
echo "🔨 添加到 app_state.nexus.chain_states (activated: true)..."

jq --arg chain "$CHAIN_NAME" '
  .app_state.nexus.chain_states += [{
    "chain": {
      "name": $chain,
      "native_asset_deprecated": "",
      "supports_foreign_assets": true,
      "key_type": "KEY_TYPE_MULTISIG",
      "module": "evm"
    },
    "activated": true,
    "assets": [],
    "maintainer_states": []
  }]
' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"

echo "   ✅ 已添加到 nexus.chain_states (activated)

"

echo ""
echo "✅ Polygon 链已成功添加到 Genesis！"
echo ""
echo "📊 配置摘要:"
echo "   - Chain: $CHAIN_NAME"
echo "   - Network: $NETWORK (Chain ID: 2501)"
echo "   - 已添加到: evm.chains, nexus.chains, nexus.chain_states"
echo ""
echo "💡 下一步: 运行 'npm start' 启动节点"
