// Right click on the script name and hit "Run" to execute

const { ethers, run } = require("hardhat");

const GAS = {
  gasLimit: 2e6,
};

const main = async () => {
  console.log("Running deploy script...");
  const TOKEN_ADDRESS = "0xBde7d92a79686E4a5771f423F81C46059e5c2222";
  const MARKET_ADDRESS = "0x9f44CCaBdeEa8a0e662485b547a05bFBf9B6DABE";
  try {
    console.log("Verifying Contracts...");
    // Verify contracts
    console.log("\n\n===> Verifyin SFA Token");
    await verifyContract(TOKEN_ADDRESS, BigInt(100_000_000 * 1e18));
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
