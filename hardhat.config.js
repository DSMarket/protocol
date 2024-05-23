require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
};

require("dotenv").config();
require("@nomicfoundation/hardhat-vyper");
require("@nomicfoundation/hardhat-waffle");
require("@nomicfoundation/hardhat-web3");
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-etherscan");

const DEPLOYER_PK = [`${process.env.DEPLOYER_PK}`];
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const BSC_RPC = process.env.BSC_RPC || "https://rpc.ankr.com/bsc";
const POLYGON_RPC = process.env.POLYGON_RPC || "https://polygon-rpc.com/";
const FANTOM_RPC = process.env.FANTOM_RPC || "https://rpcapi.fantom.network";

const LOCALHOST_RPC = process.env.LOCALHOST_RPC || "http://127.0.0.1:8545";

const config = {
  defaultNetwork: "localhost",
  networks: {
    hardhat: {},
    bsc: {
      url: BSC_RPC,
      chainId: 56,
      timeout: 600000,
      accounts: DEPLOYER_PK,
    },
    polygon: {
      url: POLYGON_RPC,
      chainId: 137,
      accounts: DEPLOYER_PK,
    },
    fantom: {
      url: FANTOM_RPC,
      chainId: 250,
      accounts: DEPLOYER_PK,
    },
    localhost: {
      url: LOCALHOST_RPC,
      timeout: 300000,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY,
  },
  vyper: {
    compilers: [{ version: "0.3.3" }],
  },
  solidity: {
    compilers: [
      {
        version: "0.6.6",
      },
      {
        version: "0.4.18",
      },
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.12",
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
