import { setupNetwork } from '@axelar-network/axelar-local-dev';
import { ethers } from 'ethers';
import { writeFileSync } from 'fs';
import { join } from 'path';

// ================= 配置区域 =================
const RPC_URL_A = 'http://localhost:8545'; // Ethereum
const RPC_URL_B = 'http://localhost:8546'; // Polygon

// 使用默认的 Hardhat/Ganache 账户私钥 (Account #0)
const PRIVATE_KEY = '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
// ===========================================

async function main(): Promise<void> {
  console.log('🚀 部署 Gateway 合约...');

  // 1. 连接节点
  const providerA = new ethers.providers.JsonRpcProvider(RPC_URL_A);
  const providerB = new ethers.providers.JsonRpcProvider(RPC_URL_B);
  const walletA = new ethers.Wallet(PRIVATE_KEY, providerA);
  const walletB = new ethers.Wallet(PRIVATE_KEY, providerB);
  const chainEthereum = 'Ethereum';
  const chainPolygon = 'Polygon';

  // 等待节点就绪
  console.log('   等待节点就绪...');
  for (let i = 0; i < 10; i++) {
    try {
      await providerA.getNetwork();
      await providerB.getNetwork();
      break;
    } catch (e) {
      if (i === 9) {
        console.error('❌ 无法连接到 EVM 节点');
        process.exit(1);
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  // 2. 部署合约
  console.log('\n🔗 部署 Ethereum Gateway...');
  const chainA = await setupNetwork(RPC_URL_A, {
    name: chainEthereum,
    ownerKey: walletA,
  });
  console.log(`   ✅ Ethereum Gateway: ${chainA.gateway.address}`);

  console.log('\n🔗 部署 Polygon Gateway...');
  const chainB = await setupNetwork(RPC_URL_B, {
    name: chainPolygon,
    ownerKey: walletB,
  });
  console.log(`   ✅ Polygon Gateway: ${chainB.gateway.address}`);

  // 3. 保存地址到文件
  const gatewayAddresses = {
    Ethereum: chainA.gateway.address,
    Polygon: chainB.gateway.address,
  };

  const outputFile = join(process.cwd(), 'chaindata', 'gateway-addresses.json');
  writeFileSync(outputFile, JSON.stringify(gatewayAddresses, null, 2));
  console.log(`\n✅ Gateway 地址已保存到: ${outputFile}`);
  console.log(JSON.stringify(gatewayAddresses, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
