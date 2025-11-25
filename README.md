# Axelar 本地跨链 Demo

这个项目演示了如何使用 `@axelar-network/axelar-local-dev` 在两个本地运行的 EVM 节点之间进行 ERC20 代币的跨链转账。

## 目录结构

- `index.js`: 核心脚本，包含连接节点、部署合约、执行跨链的所有逻辑。
- `package.json`: 项目依赖配置。

## 前置要求

1.  **Node.js**: 建议 v16 或 v18。
2.  **两个运行中的 EVM 节点**:
    你可以使用 `ganache-cli` 或 `hardhat node` 或 `anvil` 启动两个节点。
    
    **示例（使用 ganache）：**
    
    终端 1 (Chain A):
    ```bash
    npm install -g ganache
    ganache -p 8545 --chain.chainId 1337
    ```

    终端 2 (Chain B):
    ```bash
    ganache -p 8546 --chain.chainId 1338
    ```

    > 注意：确保两个节点的 Chain ID 不同，且端口分别为 8545 和 8546（或者修改 `index.js` 中的配置）。
    > 脚本中默认使用的私钥是 Ganache 默认的第一个账户私钥，如果你使用其他节点，请在 `index.js` 中更新 `PRIVATE_KEY`。

## 安装与运行

1.  **安装依赖**
    ```bash
    cd /Users/lcq/Code/axelar/axelar-demo
    npm install
    ```

2.  **运行跨链演示**
    确保两个 EVM 节点已启动，然后运行：
    ```bash
    npm start
    ```

## 脚本主要流程

1.  连接到 `localhost:8545` (Chain A) 和 `localhost:8546` (Chain B)。
2.  在两个链上自动部署 Axelar Gateway 和 Gas Service 合约（`setupNetwork` 函数完成）。
3.  在 Chain A 部署测试用的 `aUSDC` 代币并铸造余额。
4.  在 Chain B 部署对应的 `aUSDC` 代币。
5.  在 Chain A 授权 Gateway 并调用 `sendToken` 发起跨链转账。
6.  运行 `relay()` 函数模拟 Axelar 网络的中继过程。
7.  验证 Chain B 是否收到代币。

