// Right click on the script name and hit "Run" to execute

const { ethers, run } = require("hardhat");

const GAS = {
  gasLimit: 2e6,
};

const main = async () => {
  console.log("Running deploy script...");
  try {
    console.log("\n\n===> Deploy SFA Token\n\n");
    const token = await ethers.deployContract("SFAToken", [
      BigInt(100_000_000 * 1e18),
    ]);
    await token.waitForDeployment();
    console.log("Token deployed at:", token.target);
    const market = await ethers.deployContract("Market", [token.target]);
    await market.waitForDeployment();
    console.log("Market deployed at:", market.target);
    console.log(await market.owner());
  } catch (e) {
    console.log(e.message);
  }
};

const verifyContract = async (address, constructorArguments) => {
  console.log(`Verifying contract at ${address}`);
  try {
    await run("verify:verify", {
      address,
      constructorArguments,
    });
    console.log(`Contract at ${address} verified`);
  } catch (e) {
    console.log(`Verification failed for contract at ${address}: ${e.message}`);
  }
};

main();
