require("@nomicfoundation/hardhat-toolbox");
/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");
require("@nomiclabs/hardhat-solhint");
const { vars } = require("hardhat/config");

const DEPLOYER_PK = `${vars.get("DEPLOYER_PK")}`;
const ETHERSCAN_API_KEY = vars.get("ETHERSCAN_API_KEY");

const config = {
  defaultNetwork: "localhost",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      gas: 15_000_000,
    },
    sepolia: {
      url: "https://rpc.ankr.com/eth_sepolia",
      timeout: 300000,
      gas: 15_000_000,
      accounts: [DEPLOYER_PK],
    },
    hardhat: {},
  },
  sourcify: {
    // Disabled by default
    // Doesn't need an API key
    enabled: true,
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
  },
  mocha: {
    timeout: 600000,
  },
};

module.exports = config;
