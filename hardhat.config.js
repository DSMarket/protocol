require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-ethers");
require("@nomiclabs/hardhat-solhint");

const DEPLOYER_PK = [`${vars.get("DEPLOYER_PK")}`];
const ETHERSCAN_API_KEY = vars.get("ETHERSCAN_API_KEY");
const BSC_RPC = process.env.BSC_RPC || "https://rpc.ankr.com/bsc";
const POLYGON_RPC = process.env.POLYGON_RPC || "https://polygon-rpc.com/";
const FANTOM_RPC = process.env.FANTOM_RPC || "https://rpcapi.fantom.network";

const LOCALHOST_RPC = process.env.LOCALHOST_RPC || "http://127.0.0.1:8545";

const config = {
  defaultNetwork: "localhost",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      gas: 15_000_000,
    },
    hardhat: {},
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
