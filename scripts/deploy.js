// Right click on the script name and hit "Run" to execute

const { ethers } = require("hardhat");

const GAS = {
  gasLimit: 2e6,
};

const main = async () => {
  console.log("Running deploy script...");
  try {
    console.log("\n\n===> Deploy SFA Token\n\n");
    const token = await ethers.deployContract("SFAToken", [100_000_000]);
    console.log("Token deployed at:", token.target);
    const market = await ethers.deployContract("Market", [token.target]);
    console.log("Market deployed at:", market.target);
  } catch (e) {
    console.log(e.message);
  }
};

main();
