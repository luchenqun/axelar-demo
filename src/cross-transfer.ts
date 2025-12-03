import { setupNetwork, relay } from '@axelar-network/axelar-local-dev';
import { ethers } from 'ethers';

// ================= 配置区域 =================
const RPC_URL_A = 'http://localhost:8545';
const RPC_URL_B = 'http://localhost:7545';

// 使用默认的 Hardhat/Ganache 账户私钥 (Account #0)
const PRIVATE_KEY = '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
// ===========================================

async function main(): Promise<void> {
  console.log('🚀 Axelar 双向跨链演示启动 (A -> B -> A)...');

  // 1. 连接节点
  const providerA = new ethers.providers.JsonRpcProvider(RPC_URL_A);
  const providerB = new ethers.providers.JsonRpcProvider(RPC_URL_B);
  const walletA = new ethers.Wallet(PRIVATE_KEY, providerA);
  const walletB = new ethers.Wallet(PRIVATE_KEY, providerB);

  // 2. 初始化网络
  console.log('\n🔗 初始化网络环境中...');
  const chainA = await setupNetwork(RPC_URL_A, {
    name: 'ChainA',
    ownerKey: walletA,
  });
  console.log('======================');
  const chainB = await setupNetwork(RPC_URL_B, {
    name: 'ChainB',
    ownerKey: walletB,
  });

  // 3. 部署代币
  const name = 'USD Coin';
  const symbol = 'USDC';
  console.log('\n📦 部署 USDC 代币...');
  // 使用 ('USDC', 'aUSDC') 以适配 axelar-local-dev 的注册逻辑
  const usdcA = await chainA.deployToken(name, symbol, 6, BigInt(100000 * 1e6));
  const usdcB = await chainB.deployToken(name, symbol, 6, BigInt(0));

  // 自动检测 Gateway 上注册的 Token 符号

  console.log(`   👉 Detected Symbol on Gateway: ${symbol}`);
  const addr = await chainA.gateway.tokenAddresses(symbol);
  console.log('addr', addr);

  // 4. 确保余额 (解决初始余额为 0 导致转账失败的问题)
  await chainA.giveToken(walletA.address, symbol, BigInt(100000 * 1e6));

  // 打印余额函数
  const printBalances = async (label: string) => {
    const balA = await usdcA.balanceOf(walletA.address);
    const balB = await usdcB.balanceOf(walletB.address);
    console.log(`\n📊 [${label}] 余额状态:`);
    console.log(`   Chain A (Wallet): ${ethers.utils.formatUnits(balA, 6)} ${symbol}`);
    console.log(`   Chain B (Wallet): ${ethers.utils.formatUnits(balB, 6)} ${symbol}`);
  };

  await printBalances('初始状态');

  // ==================================================================
  // 第一阶段: Chain A -> Chain B
  // ==================================================================
  const amountToB = 1000 * 1e6; // 1000 USDC
  console.log(`\n👉 第一阶段: 跨链发送 ${amountToB / 1e6} ${symbol} 从 Chain A 到 Chain B`);

  const approveTx1 = await usdcA.connect(walletA).approve(chainA.gateway.address, amountToB, { gasLimit: 10000000 });
  await approveTx1.wait();

  const tx1 = await chainA.gateway.connect(walletA).sendToken('ChainB', walletB.address, symbol, amountToB, { gasLimit: 10000000 });
  await tx1.wait();
  console.log('   ✅ [Chain A] sendToken called');
  console.log('   📡 Relaying...');
  await relay();

  await printBalances('Chain A -> Chain B 完成后');

  // ==================================================================
  // 第二阶段: Chain B -> Chain A (回流)
  // ==================================================================
  const amountToA = 500 * 1e6; // 500 USDC
  console.log(`\n👈 第二阶段: 跨链回传 ${amountToA / 1e6} ${symbol} 从 Chain B 到 Chain A`);

  const approveTx2 = await usdcB.connect(walletB).approve(chainB.gateway.address, amountToA, { gasLimit: 10000000 });
  await approveTx2.wait();

  const tx2 = await chainB.gateway.connect(walletB).sendToken('ChainA', walletA.address, symbol, amountToA, { gasLimit: 10000000 });
  await tx2.wait();
  console.log('   ✅ [Chain B] sendToken called');
  console.log('   📡 Relaying...');
  await relay();

  await printBalances('最终状态');
  console.log('\n🎉 演示结束！');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
