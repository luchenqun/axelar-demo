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
  const chainB = await setupNetwork(RPC_URL_B, {
    name: 'ChainB',
    ownerKey: walletB,
  });
  console.log(`   Chain A Gateway: ${chainA.gateway.address}`);
  console.log(`   Chain B Gateway: ${chainB.gateway.address}`);

  // 3. 部署代币
  console.log('\n📦 部署 USDC 代币...');
  // Chain A 作为源链，铸造 100,000 USDC
  const usdcA = await chainA.deployToken('USDC', 'aUSDC', 6, BigInt(100000 * 1e6));
  // Chain B 作为目标链，初始供应量为 0 (代表它是 Wrapped 版本，等待跨链过来)
  const usdcB = await chainB.deployToken('USDC', 'aUSDC', 6, BigInt(0));

  console.log(`   Token A (USDC) Address: ${usdcA.address}`);
  console.log(`   Token B (aUSDC) Address: ${usdcB.address}`);

  // 打印初始余额
  const printBalances = async (label: string) => {
    const balA = await usdcA.balanceOf(walletA.address);
    const balB = await usdcB.balanceOf(walletB.address);
    console.log(`\n📊 [${label}] 余额状态:`);
    console.log(`   Chain A (Wallet): ${ethers.utils.formatUnits(balA, 6)} USDC`);
    console.log(`   Chain B (Wallet): ${ethers.utils.formatUnits(balB, 6)} aUSDC`);
  };

  await printBalances('初始状态');

  // ==================================================================
  // 第一阶段: Chain A -> Chain B
  // ==================================================================
  const amountToB = 1000 * 1e6; // 1000 USDC
  console.log(`\n👉 第一阶段: 跨链发送 ${amountToB / 1e6} USDC 从 Chain A 到 Chain B`);

  // 1. Approve Gateway A
  await (await usdcA.connect(walletA).approve(chainA.gateway.address, amountToB, { gasLimit: 10000000 })).wait();
  console.log('   ✅ [Chain A] Approved Gateway');

  // 2. Send Token
  const tx1 = await chainA.gateway.connect(walletA).sendToken('ChainB', walletB.address, 'aUSDC', amountToB, { gasLimit: 10000000 });
  await tx1.wait();
  console.log('   ✅ [Chain A] sendToken called');

  // 3. Relay
  console.log('   📡 Relaying...');
  await relay();

  await printBalances('第一阶段完成后');

  // ==================================================================
  // 第二阶段: Chain B -> Chain A (回流)
  // ==================================================================
  const amountToA = 500 * 1e6; // 500 USDC
  console.log(`\n👈 第二阶段: 跨链回传 ${amountToA / 1e6} aUSDC 从 Chain B 到 Chain A`);

  // 1. Approve Gateway B
  // 注意：在 Chain B 上，我们持有的是 'aUSDC' (Symbol可能是 USDC 或 aUSDC，取决于 deployToken 实现，但这里变量名是 usdcB)
  await (await usdcB.connect(walletB).approve(chainB.gateway.address, amountToA, { gasLimit: 10000000 })).wait();
  console.log('   ✅ [Chain B] Approved Gateway');

  // 2. Send Token Back
  // 注意：目标链是 ChainA，Token Symbol 仍然填 'aUSDC' (Axelar 内部识别符号)，或者根据 Gateway 注册的符号
  // 通常在 axelar-local-dev 中，createToken 注册的 symbol 是 'aUSDC'
  const tx2 = await chainB.gateway.connect(walletB).sendToken('ChainA', walletA.address, 'aUSDC', amountToA, { gasLimit: 10000000 });
  await tx2.wait();
  console.log('   ✅ [Chain B] sendToken called');

  // 3. Relay
  console.log('   📡 Relaying...');
  await relay();

  await printBalances('最终状态');
  console.log('\n🎉 演示结束！');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
