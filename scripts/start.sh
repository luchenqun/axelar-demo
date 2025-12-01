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
if [ -z "$(ls -A $TOFND_HOME 2>/dev/null)" ]; then
    echo "   初始化 Tofnd 密钥..."
    # 使用管道输入密码，防止交互式等待
    (echo "$TOFND_PASSWORD"; echo "$TOFND_PASSWORD") | ./bin/tofnd -m create -d $TOFND_HOME > chaindata/logs/tofnd.init.log 2>&1
    
    # 删除导出文件，避免 tofnd 再次启动报错 "File chaindata/tofnd/export already exists"
    rm -f $TOFND_HOME/export

    # 等待初始化完成
    sleep 1
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
    
    # 配置初始账户资金
    ./bin/axelard add-genesis-account validator 1000000000000000uaxl --home $AXELAR_HOME --keyring-backend test > /dev/null 2>&1
    
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

nohup ./bin/axelard start --home $AXELAR_HOME > chaindata/logs/axelard.log 2>&1 &
PID_AXELAR=$!
echo "   Axelard PID: $PID_AXELAR"

# ---------------------------
# 3. 启动 Reth (EVM 节点)
# ---------------------------
echo "3️⃣  启动 Reth 节点 (Docker)..."
mkdir -p chaindata/chain-a chaindata/chain-b
$DOCKER_COMPOSE up -d

# ---------------------------
# 4. 检查状态
# ---------------------------
echo "⏳ 等待服务启动..."
sleep 5

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

# 检查 Docker 容器
$DOCKER_COMPOSE ps

echo ""
echo "✅ 所有启动命令已执行！"
echo "   日志文件位于 chaindata/logs/"
