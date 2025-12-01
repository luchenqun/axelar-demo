import { ethers } from 'ethers';
import { setupNetwork } from '@axelar-network/axelar-local-dev';
import { execSync } from 'child_process';
import path from 'path';

// ================= 配置 =================
const RPC_URL = 'http://localhost:8545';
const CHAIN_NAME = 'Ethereum'; // 使用 genesis 中已有的链
const AXELARD_BIN = path.join(__dirname, '../bin/axelard');
const AXELAR_HOME = path.join(__dirname, '../chaindata/axelar');
const PRIVATE_KEY = '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769';
const AXELAR_CHAIN_ID = 'axelar-demo-1';

// ================= 工具函数 =================
function runAxelard(args: string): string {
  const cmd = `${AXELARD_BIN} ${args} --home ${AXELAR_HOME} --node tcp://localhost:26657 --output json`;
  try {
    return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch (e: any) {
    const stderr = e.stderr ? e.stderr.toString() : '';
    console.error(`❌ Command failed: ${cmd}`);
    console.error(`   Stderr: ${stderr}`);
    throw e;
  }
}

function runAxelardTx(args: string, from: string = 'validator') {
  const cmd = `${args} --gas auto --gas-adjustment 1.5 --keyring-backend test --from ${from} --chain-id ${AXELAR_CHAIN_ID} -y`;
  return runAxelard(cmd);
}

async function submitGovernanceProposal(title: string, description: string, message: any) {
  console.log(`\n📝 提交治理提案: ${title}`);

  // 创建提案 JSON
  const proposalFile = path.join(__dirname, '../proposal-temp.json');
  const proposal = {
    messages: [message],
    metadata: '',
    deposit: '10000000uaxl',
    title: title,
    summary: description
  };

  require('fs').writeFileSync(proposalFile, JSON.stringify(proposal, null, 2));

  try {
    // 提交提案
    const result = runAxelardTx(`tx gov submit-proposal ${proposalFile}`, 'validator');
    console.log(`   ✅ 提案已提交`);

    // 解析提案 ID
    const resultObj = JSON.parse(result);
    const proposalId = resultObj.logs?.[0]?.events
      ?.find((e: any) => e.type === 'submit_proposal')
      ?.attributes?.find((a: any) => a.key === 'proposal_id')?.value || '1';

    console.log(`   📋 提案 ID: ${proposalId}`);

    // 等待一个区块
    await new Promise(r => setTimeout(r, 2000));

    // 投票
    console.log(`   🗳️  正在投票...`);
    runAxelardTx(`tx gov vote ${proposalId} yes`, 'validator');
    console.log(`   ✅ 投票完成`);

    // 等待投票期结束（测试环境通常很短）
    console.log(`   ⏳ 等待投票期结束...`);
    await new Promise(r => setTimeout(r, 5000));

    return proposalId;
  } catch (e: any) {
    console.error(`   ❌ 治理提案失败: ${e.message}`);
    throw e;
  }
}

async function main() {
  console.log('🚀 开始简化的跨链转账测试');
  console.log('------------------------------------------------');

  // 1. 部署合约
  console.log('\n📦 1. 部署合约到 Hardhat 节点...');
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  const chain = await setupNetwork(RPC_URL, { name: CHAIN_NAME, ownerKey: wallet });

  console.log(`   Gateway: ${chain.gateway.address}`);

  // 2. 通过治理提案设置 Gateway
  console.log('\n🏛️  2. 通过治理提案设置 Gateway...');

  try {
    await submitGovernanceProposal(
      'Set Ethereum Gateway',
      `Set gateway address for ${CHAIN_NAME}`,
      {
        '@type': '/axelar.evm.v1beta1.SetGatewayRequest',
        sender: 'axelar189j23am9542swlk7p6r0g8s936dyjleyezrxnh', // validator address
        chain: CHAIN_NAME,
        address: chain.gateway.address.toLowerCase().replace('0x', '')
      }
    );
  } catch (e) {
    console.log('   ℹ️  Gateway 设置失败，可能是治理配置问题');
    console.log('   💡 建议：需要重新配置 genesis 以启用治理功能');
  }

  // 3. 部署 USDC
  console.log('\n💎 3. 部署 USDC 代币...');
  const usdc = await chain.deployToken('USDC', 'USDC', 6, BigInt(1000000000 * 1e6));
  console.log(`   USDC: ${usdc.address}`);

  // 4. Mint USDC
  console.log('\n💰 4. Mint USDC...');
  await chain.giveToken(wallet.address, 'USDC', BigInt(1000000 * 1e6));
  const balance = await usdc.balanceOf(wallet.address);
  console.log(`   余额: ${ethers.utils.formatUnits(balance, 6)} USDC`);

  console.log('\n✅ 测试完成！');
  console.log('\n⚠️  注意：');
  console.log('   - 由于权限限制，无法完成完整的跨链转账流程');
  console.log('   - 需要在 genesis 中配置治理账户才能执行管理命令');
  console.log('   - 建议使用 axelar-local-dev 的完整测试环境');
}

main().catch(console.error);
