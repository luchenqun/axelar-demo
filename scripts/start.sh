#!/bin/bash

# 确保在项目根目录执行
if [ ! -d "scripts" ]; then
  echo "❌ 错误: 请在项目根目录下运行此脚本 (例如 ./scripts/start.sh)"
  exit 1
fi

# 确保 bin 目录有 axelard 和 tofnd 文件
if [ ! -f "bin/axelard" ] || [ ! -f "bin/tofnd" ]; then
  echo "❌ 错误: bin/axelard 或 bin/tofnd 文件缺失。"
  echo "   请确保这两个可执行文件位于 bin/ 目录下。"
  exit 1
fi

# 检测 docker compose 命令
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
  DOCKER_COMPOSE="docker compose"
else
  echo "❌ 错误: 未找到 docker-compose 或 docker compose 命令"
  exit 1
fi

# 检查 jq 命令是否可用（用于修改 JSON 文件）
if ! command -v jq &> /dev/null; then
  echo "❌ 错误: 未找到 jq 命令"
  echo "   请安装 jq: brew install jq (macOS) 或 apt-get install jq (Linux)"
  exit 1
fi

echo "🚀 启动 Axelar 本地开发环境"
echo "--------------------------------"

# 创建数据和日志目录
mkdir -p chaindata/tofnd chaindata/axelar chaindata/logs

# ---------------------------
# 1. 启动 Tofnd
# ---------------------------
echo "1️⃣  启动 Tofnd..."
export TOFND_PASSWORD="123456"
TOFND_HOME="chaindata/tofnd"

# 检查是否需要初始化密钥
if [ -z "$(ls -A $TOFND_HOME 2> /dev/null)" ]; then
  echo "   初始化 Tofnd 密钥..."
  # 使用管道输入密码，防止交互式等待
  (
    echo "$TOFND_PASSWORD"
    echo "$TOFND_PASSWORD"
  ) | ./bin/tofnd -m create -d $TOFND_HOME > chaindata/logs/tofnd.init.log 2>&1

  # 删除导出文件，避免 tofnd 再次启动报错 "File chaindata/tofnd/export already exists"
  rm -f $TOFND_HOME/export
fi

echo "   正在后台启动 Tofnd..."
# 同样通过管道传入密码以防万一
(echo "$TOFND_PASSWORD") | nohup ./bin/tofnd -m existing -d $TOFND_HOME -a 0.0.0.0 -p 50051 > chaindata/logs/tofnd.log 2>&1 &
PID_TOFND=$!
echo "   Tofnd PID: $PID_TOFND"

# ---------------------------
# 2. 启动 Axelard
# ---------------------------
echo "2️⃣  启动 Axelar 节点..."
AXELAR_HOME="chaindata/axelar"
CHAIN_ID="axelar-demo-1"

# 检查是否已经初始化
if [ ! -f "$AXELAR_HOME/config/genesis.json" ]; then
  echo "   首次运行，初始化 Axelar 链配置..."

  # 初始化链
  ./bin/axelard init demo-node --chain-id $CHAIN_ID --home $AXELAR_HOME --default-denom uaxl > /dev/null 2>&1

  # 添加验证者密钥
  echo "   生成验证者密钥..."
  ./bin/axelard keys add validator --home $AXELAR_HOME --keyring-backend test --output json > $AXELAR_HOME/validator_key.json 2>&1

  # 添加 Relayer 密钥 (用于发交易，避免与 Vald Nonce 冲突)
  echo "   生成 Relayer 密钥..."
  ./bin/axelard keys add relayer --home $AXELAR_HOME --keyring-backend test --output json > $AXELAR_HOME/relayer_key.json 2>&1

  # 配置初始账户资金 (Validator)
  ./bin/axelard add-genesis-account validator 1000000000000000uaxl --home $AXELAR_HOME --keyring-backend test > /dev/null 2>&1

  # 配置初始账户资金 (Relayer) - 1,000,000,000 uaxl
  ./bin/axelard add-genesis-account relayer 1000000000000000uaxl --home $AXELAR_HOME --keyring-backend test > /dev/null 2>&1

  # 生成创世交易 (Gentx)
  ./bin/axelard genesis gentx validator 1000000000uaxl --chain-id $CHAIN_ID --home $AXELAR_HOME --keyring-backend test > /dev/null 2>&1

  # 收集 Gentx
  ./bin/axelard genesis collect-gentxs --home $AXELAR_HOME > /dev/null 2>&1

  # 验证 genesis.json 是否有效
  if ! grep -q "genutil" $AXELAR_HOME/config/genesis.json; then
    echo "   ❌ 错误: collect-gentxs 可能失败，genesis.json 不完整"
    exit 1
  fi

  # ---------------------------
  # 优化配置文件 (参考 setup-local-node.sh)
  # ---------------------------
  echo "   优化节点配置 (RPC/API/CORS)..."

  CONFIG_FILE="$AXELAR_HOME/config/config.toml"
  APP_CONFIG_FILE="$AXELAR_HOME/config/app.toml"

  if [ -f "$CONFIG_FILE" ]; then
    # 1. 修改 RPC 监听地址为 0.0.0.0 以便外部访问
    sed -i.bak 's/laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "$CONFIG_FILE"

    # 2. 启用 RPC CORS
    sed -i.bak 's/cors_allowed_origins = \[\]/cors_allowed_origins = ["*"]/' "$CONFIG_FILE"

    # 3. 减少超时时间以加快本地开发出块速度
    sed -i.bak 's/timeout_commit = "5s"/timeout_commit = "1s"/' "$CONFIG_FILE"
  fi

  if [ -f "$APP_CONFIG_FILE" ]; then
    # 1. 启用 API 服务器
    sed -i.bak 's/enable = false/enable = true/' "$APP_CONFIG_FILE"

    # 2. 启用 Swagger 文档
    sed -i.bak 's/swagger = false/swagger = true/' "$APP_CONFIG_FILE"

    # 3. 修改 API 监听地址 (0.0.0.0:1317)
    sed -i.bak 's/address = "tcp:\/\/localhost:1317"/address = "tcp:\/\/0.0.0.0:1317"/' "$APP_CONFIG_FILE"

    # 4. 启用 API CORS
    sed -i.bak 's/enabled-unsafe-cors = false/enabled-unsafe-cors = true/' "$APP_CONFIG_FILE"
  fi

  echo "   初始化完成。"
  echo "   ✅ Genesis 配置完成"
fi

# 确保 Relayer 账户存在 (避免与 Vald Nonce 冲突)
# 注意：现在已经在创世时创建了
if ! ./bin/axelard keys show relayer --home $AXELAR_HOME --keyring-backend test > /dev/null 2>&1; then
  echo "   ⚠️ Relayer 账户未找到，尝试重新导入..."
  # 如果因为某种原因丢失，尝试重新生成(但这样就没钱了，除非重新reset)
  ./bin/axelard keys add relayer --home $AXELAR_HOME --keyring-backend test > /dev/null 2>&1
fi

# ---------------------------
# 设置 Validator 权限 (ROLE_ACCESS_CONTROL)
# ---------------------------
echo "   🔧 检查并设置 Validator 权限..."
VALIDATOR_ADDRESS=$(./bin/axelard keys show validator --address --home $AXELAR_HOME --keyring-backend test 2>/dev/null || echo "")

if [ -n "$VALIDATOR_ADDRESS" ]; then
  GENESIS_FILE="$AXELAR_HOME/config/genesis.json"
  
  # 检查是否已经设置了 ROLE_ACCESS_CONTROL 权限
  HAS_PERMISSION=false
  if [ -f "$GENESIS_FILE" ]; then
    # 检查 validator 地址是否在 gov_accounts 中，并且角色是 ROLE_ACCESS_CONTROL
    if jq -e ".app_state.permission.gov_accounts[] | select(.address == \"$VALIDATOR_ADDRESS\" and (.role == \"ROLE_ACCESS_CONTROL\" or .role == 3))" "$GENESIS_FILE" > /dev/null 2>&1; then
      HAS_PERMISSION=true
    fi
  fi
  
  if [ "$HAS_PERMISSION" = false ]; then
    echo "      为 Validator 添加 ROLE_ACCESS_CONTROL 权限..."
    
    # 备份 genesis 文件
    if [ -f "$GENESIS_FILE" ]; then
      cp "$GENESIS_FILE" "${GENESIS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 检查是否已存在该地址（但角色不同）
    if jq -e ".app_state.permission.gov_accounts[] | select(.address == \"$VALIDATOR_ADDRESS\")" "$GENESIS_FILE" > /dev/null 2>&1; then
      # 更新现有条目的角色
      jq --arg addr "$VALIDATOR_ADDRESS" \
         '.app_state.permission.gov_accounts = (.app_state.permission.gov_accounts | map(if .address == $addr then .role = "ROLE_ACCESS_CONTROL" else . end))' \
         "$GENESIS_FILE" > "${GENESIS_FILE}.tmp" && mv "${GENESIS_FILE}.tmp" "$GENESIS_FILE"
    else
      # 添加新条目
      jq --arg addr "$VALIDATOR_ADDRESS" \
         '.app_state.permission.gov_accounts += [{"address": $addr, "role": "ROLE_ACCESS_CONTROL"}]' \
         "$GENESIS_FILE" > "${GENESIS_FILE}.tmp" && mv "${GENESIS_FILE}.tmp" "$GENESIS_FILE"
    fi
    
    # 验证修改是否成功
    if jq -e ".app_state.permission.gov_accounts[] | select(.address == \"$VALIDATOR_ADDRESS\" and (.role == \"ROLE_ACCESS_CONTROL\" or .role == 3))" "$GENESIS_FILE" > /dev/null 2>&1; then
      echo "      ✅ Validator 权限设置成功"
    else
      echo "      ⚠️  警告: 权限设置可能失败，请手动检查 genesis.json"
    fi
  else
    echo "      ✅ Validator 已有 ROLE_ACCESS_CONTROL 权限"
  fi
else
  echo "      ⚠️  无法获取 Validator 地址，跳过权限设置"
fi

echo "   正在后台启动 Axelard..."
# 启动节点
# 设置 bin 目录为库加载路径 (针对 Mac libwasmvm.dylib 或 Linux libwasmvm.so)
# 即使手动放置了库文件，也需要让 loader 找到它
BIN_ABS_PATH="$(cd bin && pwd)"
if [ "$(uname)" == "Darwin" ]; then
  export DYLD_LIBRARY_PATH="$BIN_ABS_PATH:$DYLD_LIBRARY_PATH"
else
  export LD_LIBRARY_PATH="$BIN_ABS_PATH:$LD_LIBRARY_PATH"
fi

# 替换 genesis.json 中的 evm.chains 配置
echo "Updating evm.chains in genesis.json..."
GENESIS_FILE="$AXELAR_HOME/config/genesis.json"
CHAINS_CONFIG="configs/chains.json"

if [ -f "$CHAINS_CONFIG" ]; then
  # 使用 jq 替换 app_state.evm.chains 的内容
  jq --argjson chains "$(cat $CHAINS_CONFIG)" '.app_state.evm.chains = $chains' "$GENESIS_FILE" > "$GENESIS_FILE.tmp" && mv "$GENESIS_FILE.tmp" "$GENESIS_FILE"
  echo "   Updated evm.chains with content from $CHAINS_CONFIG"
else
  echo "   Warning: $CHAINS_CONFIG not found, skipping evm.chains update"
fi

# 验证 genesis.json 文件
echo "Validating genesis.json with axelard..."

if ! ./bin/axelard genesis validate --home $AXELAR_HOME; then
  echo "   ERROR: Genesis validation failed"
  exit 1
fi

echo "   Genesis file validation passed"

nohup ./bin/axelard start --home $AXELAR_HOME > chaindata/logs/axelard.log 2>&1 &
PID_AXELAR=$!
echo "   Axelard PID: $PID_AXELAR"

# ---------------------------
# 3. 启动 EVM 节点 (Hardhat)
# ---------------------------
echo "3️⃣  启动 Hardhat 节点..."

# Chain A
echo "   正在启动 Chain A (Port 8545)..."
nohup npx hardhat node --config configs/chain-a.config.cjs --port 8545 > chaindata/logs/chain-a.log 2>&1 &
PID_CHAIN_A=$!
echo "   Chain A PID: $PID_CHAIN_A"

# Chain B
echo "   正在启动 Chain B (Port 7545)..."
nohup npx hardhat node --config configs/chain-b.config.cjs --port 7545 > chaindata/logs/chain-b.log 2>&1 &
PID_CHAIN_B=$!
echo "   Chain B PID: $PID_CHAIN_B"

# 启动 Vald
echo "   启动 Vald (Validator Daemon)..."
# 获取验证者地址
VALIDATOR_ADDR=$(./bin/axelard keys show validator --home $AXELAR_HOME --bech val -a --keyring-backend test)

nohup ./bin/axelard vald-start --home $AXELAR_HOME \
  --validator-addr $VALIDATOR_ADDR \
  --log_level debug \
  --chain-id $CHAIN_ID \
  --node tcp://127.0.0.1:26657 \
  --from validator \
  --keyring-backend test \
  > chaindata/logs/vald.log 2>&1 &
PID_VALD=$!
echo "   Vald PID: $PID_VALD"

# ---------------------------
# 4. 检查状态
# ---------------------------
echo "⏳ 等待服务启动..."
sleep 1

echo "📊 服务状态检查:"

# 检查 Tofnd
if ps -p $PID_TOFND > /dev/null; then
  echo "   ✅ Tofnd 运行中 (PID: $PID_TOFND)"
else
  echo "   ❌ Tofnd 启动失败，请查看日志: chaindata/logs/tofnd.log"
fi

# 检查 Axelard
if ps -p $PID_AXELAR > /dev/null; then
  echo "   ✅ Axelard 运行中 (PID: $PID_AXELAR)"
  echo "      RPC: http://localhost:26657"
else
  echo "   ❌ Axelard 启动失败，请查看日志: chaindata/logs/axelard.log"
fi

# 检查 Hardhat 节点
if ps -p $PID_CHAIN_A > /dev/null; then
  echo "   ✅ Chain A (Hardhat) 运行中 (PID: $PID_CHAIN_A)"
else
  echo "   ❌ Chain A 启动失败，请查看日志: chaindata/logs/chain-a.log"
fi

if ps -p $PID_CHAIN_B > /dev/null; then
  echo "   ✅ Chain B (Hardhat) 运行中 (PID: $PID_CHAIN_B)"
else
  echo "   ❌ Chain B 启动失败，请查看日志: chaindata/logs/chain-b.log"
fi

echo ""
echo "✅ 所有启动命令已执行！"
echo "   日志文件位于 chaindata/logs/"
