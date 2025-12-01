# Axelar 本地跨链转账实战指南

本指南将指导你利用本地搭建的 Axelar 环境（Axelard + Tofnd + Hardhat）完成一次真实的跨链 ERC20 转账。

## 1. 环境架构回顾

*   **Axelar 链**: 本地运行的 Cosmos SDK 链 (`axelar-demo-1`)，负责跨链共识和路由。
*   **Tofnd**: 门限签名守护进程，负责生成跨链交易的签名。
*   **EVM Chain A**: Hardhat 节点 (RPC: `http://localhost:8545`), 模拟源链 (Source Chain)。
*   **EVM Chain B**: Hardhat 节点 (RPC: `http://localhost:7545`), 模拟目标链 (Destination Chain)。

## 2. 跨链流程概述

在生产环境中，跨链包含以下角色和步骤：
1.  **用户**: 在源链 Gateway 合约调用 `sendToken`。
2.  **Axelar 验证者**: 监听源链事件，投票确认交易 (`confirm-gateway-tx`)。
3.  **Axelar 网络**: 达成共识，Tofnd 签署命令 (`sign-commands`)。
4.  **中继者 (Relayer)**: 获取签名和证明，调用目标链 Gateway 的 `execute` 方法。

本实战将通过一个自动化脚本 `src/real-transfer.ts` 来扮演**用户**和**中继者**的角色，与真实的 Axelar 节点交互。

## 3. 前置准备

确保所有服务已启动：
```bash
# 检查服务状态
./scripts/start.sh
# 应该看到 Tofnd, Axelard 和两个 Hardhat 节点都在运行
```

## 4. 执行跨链转账

我们提供了一个脚本来自动化整个流程，包括：
1.  在 Hardhat 节点上部署 `AxelarGateway` 和 `AxelarGasService` 合约。
2.  通过 `bin/axelard` CLI 注册链和资产。
3.  发送跨链交易。
4.  模拟 Relayer 流程（确认、签名、执行）。

### 运行脚本

```bash
npx ts-node src/real-transfer.ts
```

### 预期输出

脚本运行过程中，你应该能看到以下关键步骤的日志：
*   `📦 部署合约`: 在 Chain A 和 Chain B 上部署 Gateway。
*   `🔗 注册链`: 向 Axelar 注册 Chain A 和 Chain B。
*   `🪙 注册资产`: 注册 USDC 代币。
*   `💸 发送交易`: 调用 `sendToken`。
*   `📡 Axelar 确认`: 模拟验证者投票确认交易。
*   `✍️  Tofnd 签名`: 生成 Mint 命令的签名。
*   `🚀 目标链执行`: 在 Chain B 上铸造代币。

## 5. 手动验证 (可选)

脚本执行完毕后，你可以检查 Chain B 的余额日志，或者手动查询 Axelar 节点状态：

```bash
# 查询待处理的 EVM 命令
./bin/axelard q evm pending-commands chain-b
```

## 6. 常见问题

*   **"validator set is empty"**: 确保 `start.sh` 中的初始化步骤成功执行，并且 `axelard` 没有报错退出。
*   **"connection refused"**: 确保 Hardhat 节点 (8545/7545) 和 Axelard (26657) 端口可访问。
*   **"insufficient funds"**: 默认 Ganache 账户通常有充足的测试 ETH。如果使用自定义私钥，请确保账户有余额。

