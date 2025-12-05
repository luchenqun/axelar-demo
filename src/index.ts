import { setupNetwork, relay } from '@axelar-network/axelar-local-dev';
import { ethers } from 'ethers';

// ================= 配置区域 =================
// 假设你本地运行了两个 EVM 节点
// Ethereum: 端口 8545
// Polygon: 端口 8546
const RPC_URL_A = 'http://localhost:8545'; // Ethereum
const RPC_URL_B = 'http://localhost:8546'; // Polygon

// 这里的私钥需要是在两个链上都有余额的账户
// 为了演示方便，这里使用 Ganache 默认的第一个账户私钥
// 如果你使用自己的节点，请替换为你自己的私钥
const PRIVATE_KEY = '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
// ===========================================

async function main(): Promise<void> {
  console.log('🚀 Axelar 本地跨链演示启动...');

  // 检查节点连接
  const providerA = new ethers.providers.JsonRpcProvider(RPC_URL_A);
  const providerB = new ethers.providers.JsonRpcProvider(RPC_URL_B);

  try {
    await providerA.getNetwork();
    await providerB.getNetwork();
  } catch (e) {
    console.error('❌ 无法连接到 EVM 节点，请确保它们已启动。');
    console.error(`   节点 A: ${RPC_URL_A}`);
    console.error(`   节点 B: ${RPC_URL_B}`);
    process.exit(1);
  }

  console.log('------------------------------------------------------');

  // 设置钱包
  const walletA = new ethers.Wallet(PRIVATE_KEY, providerA);
  const walletB = new ethers.Wallet(PRIVATE_KEY, providerB);

  // 1. 初始化链 A 环境 (部署 Gateway 等 Axelar 合约)
  console.log(`\n🔗 正在初始化链 A (${RPC_URL_A})...`);
  const chainA = await setupNetwork(RPC_URL_A, {
    name: 'ChainA',
    ownerKey: walletA,
  });
  console.log(`   ✅ Gateway 地址: ${chainA.gateway.address}`);

  // 2. 初始化链 B 环境
  console.log(`\n🔗 正在初始化链 B (${RPC_URL_B})...`);
  const chainB = await setupNetwork(RPC_URL_B, {
    name: 'ChainB',
    ownerKey: walletB,
  });
  console.log(`   ✅ Gateway 地址: ${chainB.gateway.address}`);

  console.log('------------------------------------------------------');

  // 3. 部署测试代币 (ERC20)
  console.log("\n📦 正在链 A 上部署 'USDC'...");
  // deployToken 会自动 mint 初始供应量给部署者
  const tokenA = await chainA.deployToken('USDC', 'aUSDC', 6, BigInt(100000 * 1e6));
  console.log(`   ✅ Token A 地址: ${tokenA.address}`);

  console.log("\n📦 正在链 B 上部署 'USDC'...");
  // 链 B 初始供应量设为 0，因为我们将从链 A 跨链过来
  const tokenB = await chainB.deployToken('USDC', 'aUSDC', 6, BigInt(0));
  console.log(`   ✅ Token B 地址: ${tokenB.address}`);

  console.log('------------------------------------------------------');

  // 4. 跨链转账流程
  const amount = 100 * 1e6; // 100 USDC (6 decimals)
  const amountHuman = 100;

  console.log(`\n💸 准备从 Ethereum 跨链发送 ${amountHuman} USDC 到 Polygon...`);

  // 4.1 授权 Gateway
  console.log('   1️⃣  授权 Gateway 扣款...');
  const approveTx = await tokenA.connect(walletA).approve(chainA.gateway.address, amount);
  await approveTx.wait();
  console.log('       ✅ 授权完成');

  // 4.2 发送跨链交易
  console.log('   2️⃣  调用 Gateway.sendToken...');
  const sendTx = await chainA.gateway.connect(walletA).sendToken(
    chainB.name, // 目标链名称
    walletB.address, // 接收地址
    'aUSDC', // 代币 Symbol
    amount, // 数量
  );
  const receipt = await sendTx.wait();
  console.log(`       ✅ 交易已上链 (Hash: ${receipt.transactionHash})`);

  // 记录转账前余额
  const balB_before = await tokenB.balanceOf(walletB.address);

  // 4.3 执行中继 (模拟 Axelar 网络)
  console.log('\n📡 正在运行中继器 (Relayer)...');
  // relay() 会监听源链事件并在目标链执行铸造/解锁
  await relay();
  console.log('   ✅ 中继完成');

  console.log('------------------------------------------------------');

  // 5. 验证结果
  const balA = await tokenA.balanceOf(walletA.address);
  const balB = await tokenB.balanceOf(walletB.address);

  console.log('\n📊 最终余额状态:');
  console.log(`   Ethereum (Sender):   ${ethers.utils.formatUnits(balA, 6)} aUSDC`);
  console.log(`   Polygon (Receiver): ${ethers.utils.formatUnits(balB, 6)} aUSDC`);

  if (balB.gt(balB_before)) {
    console.log(`\n🎉 成功！Polygon 收到了跨链资产！`);
  } else {
    console.log(`\n⚠️  Polygon 余额未增加，请检查日志。`);
  }
}

main().catch((err) => {
  console.error('\n❌ 发生错误:');
  console.error(err);
  process.exit(1);
});
