/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    hardhat: {
      chainId: 1,
      hardfork: 'shanghai', // Use a stable hardfork compatible with axelar contracts
      accounts: [
        {
          privateKey: '0xf78a036930ce63791ea6ea20072986d8c3f16a6811f6a2583b0787c45086f769',
          balance: '10000000000000000000000', // 10000 ETH
        },
      ],
    },
  },
};
