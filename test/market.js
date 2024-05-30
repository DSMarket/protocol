const hre = require("hardhat");
const ethers = hre.ethers;
const { expect } = require("chai");

describe("Market Contract", function () {
  let market, token;
  let signers,
    owner,
    keeper,
    host1,
    host2,
    sentinel1,
    sentinel2,
    sentinel3,
    sentinel4,
    sentinel5,
    addr1;
  const initialBalance = ethers.parseEther("100000");
  let now = Math.trunc(new Date().getTime() / 1000);

  before(async function () {
    signers = await ethers.getSigners();
    [
      owner,
      keeper,
      host1,
      host2,
      sentinel1,
      sentinel2,
      sentinel3,
      sentinel4,
      sentinel5,
      addr1,
    ] = signers;

    // Deploy an ERC20 token and ERC721 Market
    token = await ethers.deployContract("SFAToken", [initialBalance]);
    // console.log("Token deployed at:", token.target);

    market = await ethers.deployContract("Market", [token.target]);
    // console.log("Market deployed at:", market.target);

    // Transfer tokens to other accounts
    await token.transfer(keeper.address, initialBalance / BigInt(10));
    await token.connect(keeper).approve(market.target, ethers.MaxUint256);
    await token.transfer(sentinel1.address, initialBalance / BigInt(10));
    await token.connect(sentinel1).approve(market.target, ethers.MaxUint256);
    await token.transfer(sentinel2.address, initialBalance / BigInt(10));
    await token.connect(sentinel2).approve(market.target, ethers.MaxUint256);
    await token.transfer(sentinel3.address, initialBalance / BigInt(10));
    await token.connect(sentinel3).approve(market.target, ethers.MaxUint256);
    await token.transfer(sentinel4.address, initialBalance / BigInt(10));
    await token.connect(sentinel4).approve(market.target, ethers.MaxUint256);
    await token.transfer(sentinel5.address, initialBalance / BigInt(10));
    await token.connect(sentinel5).approve(market.target, ethers.MaxUint256);
    await token.transfer(host1.address, initialBalance / BigInt(10));
    await token.connect(host1).approve(market.target, ethers.MaxUint256);
    await token.transfer(addr1.address, initialBalance / BigInt(10));
    await token.connect(addr1).approve(market.target, ethers.MaxUint256);

    // Setup roles
    const tx1 = await market.connect(owner).setKeeper(keeper.address, true);
    tx1.wait();
    const tx2 = await market.connect(sentinel1).registerSentinel();
    tx2.wait();
    const tx3 = await market.connect(sentinel2).registerSentinel();
    tx3.wait();
    const tx4 = await market.connect(sentinel3).registerSentinel();
    tx4.wait();
    const tx5 = await market.connect(sentinel4).registerSentinel();
    tx5.wait();
    const tx6 = await market.connect(sentinel5).registerSentinel();
    tx6.wait();
    await market
      .connect(host1)
      .registerHost(
        "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWFR4LxFMDyAfA8zz627szRUfEexykFjdTqHUPvDRXtgfz"
      );

    const block = await ethers.provider.getBlock("latest");
    now = Number(block.timestamp);
    // Create SFAs
    const tx = await market.connect(addr1).createSFA(
      "bafybeihkoviema7g3gxyt6la7vd5ho32ictqbilu3wnlo3rs7ewhnp7lly",
      BigInt(1e18),
      now + 3600, // plus an hour
      86_400
    );
    await tx.wait();
    await market.connect(host1).claimHost(1);
  });

  describe("Owner Functions", function () {
    it("should allow the owner to set a keeper", async function () {
      await market.connect(owner).setKeeper(addr1.address, true);
      expect(await market.keepers(addr1.address)).to.be.true;
    });
    it("should allow the owner to update sentinel status", async function () {
      await market.connect(owner).updateSentinelStatus(sentinel1.address, 1); // ACTIVE
      expect((await market.sentinels(sentinel1.address)).status).to.equal(1); // ACTIVE
    });
  });

  describe("Keeper Functions", function () {
    it("should allow keepers to update SFA status", async function () {
      // Assume we have a created SFA with id 1
      await market.connect(keeper).updateSFAStatus(1, 1); // ACTIVE
      expect((await market.sfas(1)).status).to.equal(1); // ACTIVE
    });

    it("should allow keepers to pause withdrawals", async function () {
      await market.connect(keeper).setPauseWithdrawals(addr1.address, true);
      expect(await market.withdrawalPaused(addr1.address)).to.be.true;
    });

    it("should allow keepers to set panic mode ON", async function () {
      await market.connect(keeper).setPanic(true);
      expect(await market.panic()).to.be.true;
    });

    it("should allow keepers to set panic mode OFF", async function () {
      await market.connect(keeper).setPanic(false);
      expect(await market.panic()).to.be.false;
    });
  });

  describe("Sentinel Functions", function () {
    it("should allow sentinels to register", async function () {
      const tx = await market.connect(addr1).registerSentinel();
      await tx.wait();
      expect((await market.sentinels(addr1.address)).status).to.equal(1); // ACTIVE
    });

    it("should allow sentinels to create disputes", async function () {
      await market
        .connect(sentinel1)
        .createDispute(
          1,
          "Test Dispute",
          "Description",
          now - 7200,
          now - 3600
        );
      expect((await market.disputes(0)).claimant).to.equal(sentinel1.address);
    });

    it("should allow sentinels to commit and reveal votes", async function () {
      const prevDisputeId = Number(await market.disputeCounter()) - 1;
      const disputeId = prevDisputeId + 1;
      await market
        .connect(sentinel1)
        .createDispute(
          1,
          "Test Dispute 2",
          "Description 2",
          now - 7200,
          now - 3600
        );

      const arbitrators = await market.disputeArbitrators(disputeId);

      const arbitrator = signers.find((s) =>
        arbitrators.find((a) => s.address == a)
      );

      const vote = 1; // YES
      const salt = 1234;
      const commitment = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["uint8", "uint256"],
          [vote, salt]
        )
      );
      const committedVote = await market
        .connect(arbitrator)
        .commitVote(disputeId, commitment);
      await committedVote.wait();
      const tx = await market.disputeCommitments(disputeId, arbitrator.address);

      expect(tx).to.equal(commitment);

      // Increase time to pass the deadline
      await ethers.provider.send("evm_increaseTime", [3610]);
      const block = await ethers.provider.getBlock("latest");
      now = block.timestamp;
      const revealVoteTx = await market
        .connect(arbitrator)
        .revealVote(disputeId, vote, salt);
      await revealVoteTx.wait();
      // const voted = await market.disputeVotes(arbitrator.address);
      // console.log({ voted });
      // expect(voted).to.be.equal(vote);
      // expect(await market.disputeVotes(arbitrator.address)).to.equal(vote);
    });
  });

  describe("Host Functions", function () {
    it("should allow hosts to register", async function () {
      await market.connect(host2).registerHost("multiaddress");
      expect((await market.hosts(host2.address)).status).to.equal(1); // ACTIVE
    });

    it("should allow hosts to claim an SFA", async function () {
      // Assume we have a created SFA with id 2
      const block = await ethers.provider.getBlock("latest");
      now = Number(block.timestamp);
      const tx = await market.connect(addr1).createSFA(
        "bafybeihkoviema7g3gxyt6la7vd5ho32ictqbilu3wnlo3rs7ewhnp7lly",
        BigInt(1e18),
        now + 3600, // plus an hour
        86_400
      );
      await tx.wait();
      const sfaCounter = Number(await market.sfaCounter());
      await market.connect(host1).claimHost(sfaCounter);
      expect((await market.sfas(sfaCounter)).host).to.equal(host1.address);
    });
  });

  describe("Vesting and Withdraw", function () {
    it("should allow hosts to claim vesting", async function () {
      // Assume we have a created and active SFA with id 1
      const block = await ethers.provider.getBlock("latest");
      now = Number(block.timestamp);
      const tx = await market
        .connect(addr1)
        .createSFA("cid", BigInt(1e18), now + 3600, 7200);
      await tx.wait();
      const sfaCounter = Number(await market.sfaCounter());
      await market.connect(host1).claimHost(sfaCounter);
      await ethers.provider.send("evm_increaseTime", [3610]); // Increase time to pass the start time
      const tx2 = await market.connect(host1).claimVesting(sfaCounter);
      await tx2.wait();
      expect(await market.tokenBalances(host1.address)).to.be.gt(0);
    });

    it("should allow users to withdraw their balance", async function () {
      const block = await ethers.provider.getBlock("latest");
      now = Number(block.timestamp);
      await market
        .connect(owner)
        .createSFA("cid", BigInt(1e18), now + 3600, 7200);
      const sfaCounter = Number(await market.sfaCounter());
      await market.connect(host1).claimHost(sfaCounter);
      await ethers.provider.send("evm_increaseTime", [3601]); // Increase time to pass the start time
      await market.connect(host1).claimVesting(sfaCounter);

      const balanceBefore = await token.balanceOf(host1.address);
      await market.connect(host1).withdraw(host1.address, BigInt(1e18));
      const balanceAfter = await token.balanceOf(host1.address);

      expect(balanceAfter - balanceBefore).to.equal(BigInt(1e18));
    });
  });
});
