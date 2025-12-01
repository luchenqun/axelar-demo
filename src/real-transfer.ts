import { ethers } from 'ethers';
import { setupNetwork } from '@axelar-network/axelar-local-dev';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

// ================= 配置 =================
const RPC_URL_A = 'http://localhost:8545';
const RPC_URL_B = 'http://localhost:7545';
const CHAIN_A_NAME = 'Ethereum'; // 使用 genesis 中已有的链
const CHAIN_B_NAME = 'Polygon';   // 运行时添加的新链
const AXELARD_BIN = path.join(__dirname, '../bin/axelard');
const AXELAR_HOME = path.join(__dirname, '../chaindata/axelar');
const PRIVATE_KEY = '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769'; // Ganache Default
const AXELAR_CHAIN_ID = 'axelar-demo-1';
// const BurnableMintableCappedERC20 = require('@axelar-network/axelar-cgp-solidity/artifacts/contracts/BurnableMintableCappedERC20.sol/BurnableMintableCappedERC20.json');

// ================= 工具函数 =================
function runAxelard(args: string): string {
  // 移除 --output json，因为某些命令出错时 json 格式可能包含额外信息导致解析失败，或者命令本身不支持
  // 同时显式指定 --node 参数，防止环境变量干扰
  const cmd = `${AXELARD_BIN} ${args} --home ${AXELAR_HOME} --node tcp://localhost:26657 --output json`;
  try {
    // console.log(`执行: ${cmd}`);
    // Capture stdout and stderr (stdio: ['ignore', 'pipe', 'pipe'])
    return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch (e: any) {
    const stdout = e.stdout ? e.stdout.toString() : '';
    const stderr = e.stderr ? e.stderr.toString() : '';
    console.error(`❌ Command failed: ${cmd}`);
    // console.error(`   Stdout: ${stdout}`); // Stdout is usually JSON output or empty on error
    console.error(`   Stderr: ${stderr}`);
    throw e;
  }
}

function runAxelardTx(args: string, from: string = 'relayer') {
  // 交易需要 keyring-backend test
  const cmd = `${args} --gas auto --gas-adjustment 1.5 --keyring-backend test --from ${from} --chain-id ${AXELAR_CHAIN_ID} -y`;
  return runAxelard(cmd);
}

async function main() {
  console.log('🚀 开始真实环境跨链转账测试 (Real Axelar Node)');
  console.log('------------------------------------------------');

  const providerA = new ethers.providers.JsonRpcProvider(RPC_URL_A);
  const providerB = new ethers.providers.JsonRpcProvider(RPC_URL_B);
  const walletA = new ethers.Wallet(PRIVATE_KEY, providerA);
  const walletB = new ethers.Wallet(PRIVATE_KEY, providerB);

  // 1. 在 EVM 链上部署 Gateway 和 Token
  console.log('\n📦 1. 部署合约到 Hardhat 节点...');

  // 使用 setupNetwork 帮助我们快速部署 Gateway 合约
  // 注意：setupNetwork 默认会尝试在内部 mock axelar，但我们只用它来部署合约
  const chainA = await setupNetwork(RPC_URL_A, { name: CHAIN_A_NAME, ownerKey: walletA });
  const chainB = await setupNetwork(RPC_URL_B, { name: CHAIN_B_NAME, ownerKey: walletB });

  console.log(`   Chain A Gateway: ${chainA.gateway.address}`);
  console.log(`   Chain B Gateway: ${chainB.gateway.address}`);

  // 部署 USDC
  console.log('   部署 USDC 代币 (Using chain.deployToken)...');
  // Note: chain.deployToken registers the token on the Gateway and makes the Gateway the minter.
  const usdcA = await chainA.deployToken('USDC', 'USDC', 6, BigInt(1000000000 * 1e6));
  const usdcB = await chainB.deployToken('USDC', 'USDC', 6, BigInt(1000000000 * 1e6));

  console.log(`   USDC A: ${usdcA.address}`);
  console.log(`   USDC B: ${usdcB.address}`);

  // Mint USDC to walletA (Sender) via Gateway
  console.log('   Minting USDC to walletA (via Gateway)...');
  try {
    await chainA.giveToken(walletA.address, 'USDC', BigInt(1000000 * 1e6));
    console.log(`   ✅ Minted 1,000,000 USDC to ${walletA.address}`);
  } catch (e: any) {
    console.log(`   ⚠️  Mint failed: ${e.message}`);
  }

  // DEBUG: Check if Gateway knows about USDC
  const usdcAddressOnGatewayA = await chainA.gateway.tokenAddresses('USDC');
  console.log(`   [DEBUG] Chain A Gateway 'USDC' address: ${usdcAddressOnGatewayA}`);
  if (usdcAddressOnGatewayA === ethers.constants.AddressZero) {
    console.error('   ❌ Chain A Gateway does not have USDC registered! sendToken will fail.');
  } else {
    console.log('   ✅ Chain A Gateway recognizes USDC.');
  }

  // 2. 在 Axelar 节点上注册 Gateway 地址和资产
  console.log('\n🔗 2. 在 Axelar 核心注册 Gateway 和资产...');

  // 2.1 检查链是否已注册
  console.log(`   ℹ️  ${CHAIN_A_NAME} 和 ${CHAIN_B_NAME} 已在 genesis 中注册`);

  // 2.2 注册 Gateway 地址
  try {
    runAxelardTx(`tx evm set-gateway ${CHAIN_A_NAME} ${chainA.gateway.address}`, 'validator');
    console.log(`   ✅ 设置 ${CHAIN_A_NAME} Gateway: ${chainA.gateway.address}`);
  } catch (e) {
    console.log(`   ℹ️  Gateway 设置失败或已设置`);
  }

  try {
    runAxelardTx(`tx evm set-gateway ${CHAIN_B_NAME} ${chainB.gateway.address}`, 'validator');
    console.log(`   ✅ 设置 ${CHAIN_B_NAME} Gateway: ${chainB.gateway.address}`);
  } catch (e) {
    console.log(`   ℹ️  Gateway 设置失败或已设置`);
  }

  // 2.3 注册资产 (USDC)
  // create-deploy-token 命令会告诉 Axelar 这个 token 可以在哪些链上部署/跨链
  // 格式: create-deploy-token [chain] [origin_chain] [origin_symbol] [name] [symbol] [decimals] [capacity] [daily_mint_limit]
  try {
    // 这是一个简化的注册方式，实际上可能需要更多步骤
    // 我们尝试注册一个名为 "USDC" 的代币
    // 注意：Axelar 需要先注册代币元数据
    // 这里的 origin_chain 写 chain-a
    runAxelardTx(`tx evm create-deploy-token ${CHAIN_B_NAME} ${CHAIN_A_NAME} USDC "USD Coin" USDC 6 1000000000000000 1000000000000000`, 'validator');
    console.log(`   ✅ 注册 USDC 资产`);
  } catch (e) {
    // 如果失败，可能是已经注册了，或者是命令参数问题
    console.log(`   ℹ️  USDC 可能已注册`);
  }

  // 3. 发起跨链转账
  const amount = 100 * 1e6;
  console.log(`\n💸 3. 发起跨链转账: 100 USDC from ${CHAIN_A_NAME} -> ${CHAIN_B_NAME}`);

  // 3.1 Approve
  await (await usdcA.connect(walletA).approve(chainA.gateway.address, amount, { gasLimit: 3000000 })).wait();
  console.log('   ✅ 授权完成');

  // DEBUG: Check Allowance and Balance
  const allowance = await usdcA.allowance(walletA.address, chainA.gateway.address);
  const balance = await usdcA.balanceOf(walletA.address);
  console.log(`   [DEBUG] Allowance: ${allowance.toString()}`);
  console.log(`   [DEBUG] Balance:   ${balance.toString()}`);
  console.log(`   [DEBUG] Amount:    ${amount.toString()}`);

  if (allowance.lt(amount)) {
    console.error('   ❌ Allowance is less than amount!');
  }
  if (balance.lt(amount)) {
    console.error('   ❌ Balance is less than amount!');
  }

  // 3.2 Send Token
  const tx = await chainA.gateway.connect(walletA).sendToken(CHAIN_B_NAME, walletB.address, 'USDC', amount, { gasLimit: 3000000 });
  const receipt = await tx.wait();
  console.log(`   ✅ 交易已上链: ${receipt.transactionHash}`);

  // 4. 模拟 Relayer 流程
  console.log('\n📡 4. 开始 Relayer 流程 (模拟验证者和中继者)...');

  // 4.1 确认交易 (Confirm)
  // axelard tx evm confirm-gateway-txs [chain] [txID]...
  console.log('   🔄 [Axelar] 确认 Gateway 交易...');
  try {
    // Use confirm-gateway-txs (plural)
    runAxelardTx(`tx evm confirm-gateway-txs ${CHAIN_A_NAME} ${receipt.transactionHash}`);
    console.log('   ✅ 交易确认成功');
  } catch (e) {
    console.log('   ❌ 确认失败 (可能需要等待几个区块或已经确认)');
  }

  // 等待确认生效
  await new Promise((r) => setTimeout(r, 2000));

  // 4.3 签署命令 (Sign Commands)
  console.log('   ✍️  [Axelar] 签署命令...');
  let signResult = '';
  try {
    signResult = runAxelardTx(`tx evm sign-commands ${CHAIN_B_NAME}`);
    console.log('   ✅ 签名请求已发送');
  } catch (e) {
    console.log('   ⚠️  签名请求失败 (可能没有待处理的命令)');
  }

  // 4.4 获取 Batch ID 和 Proof
  // 我们需要轮询，直到 batch 状态为 BATCHED_COMMANDS_STATUS_SIGNED
  console.log('   ⏳ 等待签名完成...');

  // 获取最新的 batch ID
  // axelard q evm batched-commands [chain]
  // 这是一个复杂的查询，为了简化，我们尝试直接获取签名的命令执行数据
  // axelard q evm gateway-command-data [chain] [command_id] ?

  // 更简单的方法：使用 axelar-local-dev 的 relay，但它可能无法连接我们的 axelard
  // 我们手动来。

  // 这里的难点是获取刚刚生成的 batch ID 和 proof。
  // 我们可以查询最新的 batch
  let executeData = '';
  for (let i = 0; i < 10; i++) {
    try {
      // 获取 execute-data (这是可以直接提交给 Gateway 的数据)
      // 命令: axelard q evm pending-commands [chain] (这只是查看)
      // 命令: axelard q evm batched-commands [chain] --limit 1 --order desc
      // 从结果中提取 execute_data (需要是 HEX)

      // 注意：axelard q evm batched-commands [chain] [id] 需要ID。
      // 我们改用 q evm latest-batched-commands [chain] 来获取最新的
      const cmdOutput = runAxelard(`q evm latest-batched-commands ${CHAIN_B_NAME}`);
      const latestBatch = JSON.parse(cmdOutput);

      if (latestBatch.status === 'BATCHED_COMMANDS_STATUS_SIGNED') {
        // 获取 execute_data
        executeData = latestBatch.execute_data;
        if (executeData) {
          console.log(`   ✅ 获取到执行数据: ${executeData.substring(0, 20)}...`);
          break;
        }
      }
    } catch (e) {}
    await new Promise((r) => setTimeout(r, 2000));
  }

  if (!executeData) {
    // 如果上面的查询失败，尝试使用 AxelarJS SDK 或 fallback
    // 这里我们做个假设：如果自动签名成功，Tofnd 会生成 proof
    // 实际上 CLI 交互比较难拿到 proof hex。
    // 我们尝试使用 create-execute-data 命令?
    // axelard q evm latest-batched-commands [chain]
    try {
      const cmdOutput = runAxelard(`q evm latest-batched-commands ${CHAIN_B_NAME}`);
      const latest = JSON.parse(cmdOutput);
      if (latest.execute_data) {
        executeData = latest.execute_data;
        console.log(`   ✅ 获取到执行数据 (Latest): ${executeData.substring(0, 20)}...`);
      }
    } catch (e) {
      console.log('   ❌ 无法获取执行数据 (Proof)，流程终止。请检查 Tofnd 日志。');
      return;
    }
  }

  if (!executeData) {
    console.log('   ❌ 执行数据为空，退出。');
    return;
  }

  // 4.5 执行 (Execute)
  console.log(`\n🚀 5. 在 ${CHAIN_B_NAME} 执行 Mint...`);
  // executeData 是 hex string，包含 commandId, source, sourceTx, etc. 签名
  // 格式化 0x
  if (!executeData.startsWith('0x')) executeData = '0x' + executeData;

  try {
    const execTx = await chainB.gateway.connect(walletB).execute(executeData, { gasLimit: 3000000 });
    await execTx.wait();
    console.log('   ✅ 执行成功！资产已铸造。');
  } catch (e: any) {
    console.log(`   ❌ 执行失败: ${e.message}`);
  }

  // 5. 验证余额
  const balB = await usdcB.balanceOf(walletB.address);
  console.log(`\n📊 最终 Chain B 余额: ${ethers.utils.formatUnits(balB, 6)} USDC`);
}

main().catch(console.error);
