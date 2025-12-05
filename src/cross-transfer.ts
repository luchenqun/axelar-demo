import { setupNetwork, relay } from '@axelar-network/axelar-local-dev';
import { ethers } from 'ethers';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// ================= 配置区域 =================
const RPC_URL_A = 'http://localhost:8545'; // Ethereum
const RPC_URL_B = 'http://localhost:8546'; // Polygon

// 使用默认的 Hardhat/Ganache 账户私钥 (Account #0)
const PRIVATE_KEY = '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
// ===========================================

async function sleep(timeout: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve();
    }, timeout);
  });
}

async function registerGateway(chain: string, gatewayAddress: string): Promise<void> {
  const command = `./bin/axelard tx evm set-gateway ${chain} ${gatewayAddress} --from validator -y --home ./chaindata/axelar --keyring-backend test`;
  console.log(`📝 注册 Gateway 地址: ${chain} -> ${gatewayAddress}`);
  try {
    const { stdout, stderr } = await execAsync(command);
    if (stderr) {
      console.error(`   ⚠️  stderr: ${stderr}`);
    }
    console.log(`   ✅ Gateway 注册成功`);
  } catch (error) {
    console.error(`   ❌ Gateway 注册失败:`, error);
    throw error;
  }
}

async function main(): Promise<void> {
  console.log('🚀 Axelar 双向跨链演示启动 (A -> B -> A)...');

  // 1. 连接节点
  const providerA = new ethers.providers.JsonRpcProvider(RPC_URL_A);
  const providerB = new ethers.providers.JsonRpcProvider(RPC_URL_B);
  const walletA = new ethers.Wallet(PRIVATE_KEY, providerA);
  const walletB = new ethers.Wallet(PRIVATE_KEY, providerB);
  const chainEthereum = 'Ethereum';
  const chainPolygon = 'Polygon';

  // 2. 初始化网络
  console.log('\n🔗 初始化网络环境中...');
  const chainA = await setupNetwork(RPC_URL_A, {
    name: chainEthereum,
    ownerKey: walletA,
  });
  console.log('======================');
  const chainB = await setupNetwork(RPC_URL_B, {
    name: chainPolygon,
    ownerKey: walletB,
  });

  // 2.1 注册 Gateway 地址到 Axelar Core
  console.log('\n🔗 注册 Gateway 地址到 Axelar Core...');
  await registerGateway(chainEthereum, chainA.gateway.address);
  await registerGateway(chainPolygon, chainB.gateway.address);

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
    console.log(`   Ethereum (Wallet): ${ethers.utils.formatUnits(balA, 6)} ${symbol}`);
    console.log(`   Polygon (Wallet): ${ethers.utils.formatUnits(balB, 6)} ${symbol}`);
  };

  await printBalances('初始状态');

  // ==================================================================
  // 第一阶段: Ethereum -> Polygon
  // ==================================================================
  const amountToB = 1000 * 1e6; // 1000 USDC
  console.log(`\n👉 第一阶段: 跨链发送 ${amountToB / 1e6} ${symbol} 从 Ethereum 到 Polygon`);

  const approveTx1 = await usdcA.connect(walletA).approve(chainA.gateway.address, amountToB, { gasLimit: 10000000 });
  await approveTx1.wait();

  const tx1 = await chainA.gateway.connect(walletA).sendToken(chainPolygon, walletB.address, symbol, amountToB, { gasLimit: 10000000 });
  await tx1.wait();
  console.log('   ✅ [Ethereum] sendToken called', tx1.hash);
  console.log('   📡 Relaying...');

  // await relay();

  await sleep(2000);

  await printBalances('Ethereum -> Polygon 完成后');

  // // ==================================================================
  // // 第二阶段: Polygon -> Ethereum (回流)
  // // ==================================================================
  // const amountToA = 500 * 1e6; // 500 USDC
  // console.log(`\n👈 第二阶段: 跨链回传 ${amountToA / 1e6} ${symbol} 从 Polygon 到 Ethereum`);

  // const approveTx2 = await usdcB.connect(walletB).approve(chainB.gateway.address, amountToA, { gasLimit: 10000000 });
  // await approveTx2.wait();

  // const tx2 = await chainB.gateway.connect(walletB).sendToken(chainEthereum, walletA.address, symbol, amountToA, { gasLimit: 10000000 });
  // await tx2.wait();
  // console.log('   ✅ [Polygon] sendToken called');
  // console.log('   📡 Relaying...');
  // await relay();

  // await printBalances('最终状态');
  // console.log('\n🎉 演示结束！');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
