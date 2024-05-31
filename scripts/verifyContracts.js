// Right click on the script name and hit "Run" to execute

const { ethers, run } = require("hardhat");

const GAS = {
  gasLimit: 2e6,
};

const main = async () => {
  console.log("Running deploy script...");
  const TOKEN_ADDRESS = "0x890521272a46306a1d4589a6c0c39f80813db0dc";
  const MARKET_ADDRESS = "0x5418c03638711c7d5ed6fb34542485a1f6d8ff24";
  try {
    console.log("Verifying Contracts...");
    // Verify contracts
    console.log("\n\n===> Verifyin SFA Token");
    await verifyContract(TOKEN_ADDRESS, [100_000_000]);
    console.log("done");
    console.log("\n\n===> Verifyin SFA Market");
    await verifyContract(MARKET_ADDRESS, [TOKEN_ADDRESS]);
    console.log("done");
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
