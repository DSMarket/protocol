const hre = require("hardhat");
const ethers = hre.ethers;
const { expect } = require("chai");

describe("Market Contract", function () {
  let market, token;
  let owner,
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
  const now = new Date().getTime();

  before(async function () {
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
    ] = await ethers.getSigners();

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
    await market
      .connect(host2)
      .registerHost(
        "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWFR4LxFMDyAfA8zz627szRUfEexykFjdTqHUPvDRXtgfz"
      );

    // Create SFAs
    const sfaCreated1 = await market.connect(addr1).createSFA(
      "bafybeihkoviema7g3gxyt6la7vd5ho32ictqbilu3wnlo3rs7ewhnp7lly",
      BigInt(1e18),
      now + 3600, // plus a minute
      86_400
    );

    // make host claim 1st SFA
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
          now + 3600
        );
      expect((await market.disputes(0)).claimant).to.equal(sentinel1.address);
    });

    it("should allow sentinels to commit and reveal votes", async function () {
      const disputeId = 0;
      await market
        .connect(sentinel1)
        .createDispute(
          1,
          "Test Dispute",
          "Description",
          Math.floor(Date.now() / 1000),
          Math.floor(Date.now() / 1000) + 3600
        );

      const vote = 1; // YES
      const salt = 1234;
      const commitment = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["uint8", "uint256"],
          [vote, salt]
        )
      );
      await market.connect(sentinel1).commitVote(disputeId, commitment);

      expect(
        (await market.disputes(disputeId)).commitments(sentinel1.address)
      ).to.equal(commitment);

      await ethers.provider.send("evm_increaseTime", [3600]); // Increase time to pass the deadline
      await market.connect(sentinel1).revealVote(disputeId, vote, salt);

      expect(
        (await market.disputes(disputeId)).votes(sentinel1.address)
      ).to.equal(vote);
    });
  });

  describe("Host Functions", function () {
    it("should allow hosts to register", async function () {
      await market.connect(host1).registerHost("multiaddress");
      expect((await market.hosts(host.address)).status).to.equal(1); // ACTIVE
    });

    it("should allow hosts to claim an SFA", async function () {
      // Assume we have a created SFA with id 1
      await token.connect(host1).approve(market.address, ethers.MaxUint256);
      await market.connect(host1).claimHost(1);
      expect((await market.sfas(1)).host).to.equal(host.address);
    });
  });

  describe("Vesting and Withdraw", function () {
    it("should allow hosts to claim vesting", async function () {
      // Assume we have a created and active SFA with id 1
      await market
        .connect(owner)
        .createSFA(
          "cid",
          ethers.parseEther("100"),
          Math.floor(Date.now() / 1000) + 3600,
          7200
        );
      await token.connect(host1).approve(market.address, ethers.MaxUint256);
      await market.connect(host1).claimHost(1);
      await ethers.provider.send("evm_increaseTime", [3600]); // Increase time to pass the start time

      await market.connect(host1).claimVesting(1);
      expect(await market.tokenBalances(host.address)).to.be.gt(0);
    });

    it("should allow users to withdraw their balance", async function () {
      await market
        .connect(owner)
        .createSFA(
          "cid",
          ethers.parseEther("100"),
          Math.floor(Date.now() / 1000) + 3600,
          7200
        );
      await token.connect(host1).approve(market.address, ethers.MaxUint256);
      await market.connect(host1).claimHost(1);
      await ethers.provider.send("evm_increaseTime", [3600]); // Increase time to pass the start time
      await market.connect(host1).claimVesting(1);

      const balanceBefore = await token.balanceOf(host.address);
      await market
        .connect(host1)
        .withdraw(host.address, ethers.parseEther("10"));
      const balanceAfter = await token.balanceOf(host.address);

      expect(balanceAfter.sub(balanceBefore)).to.equal(ethers.parseEther("10"));
    });
  });
});
