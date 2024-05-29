const { ethers } = require("hardhat");

describe("Market Contract", function () {
  let Market, market;
  let owner, keeper, sentinel, host, addr1;
  let token, Token;
  const initialBalance = ethers.utils.parseEther("1000");

  beforeEach(async function () {
    // Deploy an ERC20 token for testing
    Token = await ethers.getContractFactory("SFAToken");
    token = await Token.deploy("SFA Token", "SFAT", initialBalance);
    await token.deployed();

    // Deploy the Market contract
    Market = await ethers.getContractFactory("Market");
    [owner, keeper, sentinel, host, addr1, ...addrs] =
      await ethers.getSigners();
    market = await Market.deploy(token.address);
    await market.deployed();

    // Transfer tokens to other accounts
    await token.transfer(keeper.address, initialBalance.div(4));
    await token.transfer(sentinel.address, initialBalance.div(4));
    await token.transfer(host.address, initialBalance.div(4));
    await token.transfer(addr1.address, initialBalance.div(4));

    // Setup roles
    await market.connect(owner).setKeeper(keeper.address, true);
    await market.connect(sentinel).registerSentinel();
  });

  describe("Owner Functions", function () {
    it("should allow the owner to set a keeper", async function () {
      await market.connect(owner).setKeeper(addr1.address, true);
      expect(await market.keepers(addr1.address)).to.be.true;
    });

    it("should allow the owner to update sentinel status", async function () {
      await market.connect(owner).updateSentinelStatus(sentinel.address, 1); // ACTIVE
      expect((await market.sentinels(sentinel.address)).status).to.equal(1); // ACTIVE
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

    it("should allow keepers to set panic mode", async function () {
      await market.connect(keeper).setPanic(true);
      expect(await market.panic()).to.be.true;
    });
  });

  describe("Sentinel Functions", function () {
    it("should allow sentinels to register", async function () {
      await token
        .connect(addr1)
        .approve(market.address, ethers.utils.parseEther("30"));
      await market.connect(addr1).registerSentinel();
      expect((await market.sentinels(addr1.address)).status).to.equal(1); // ACTIVE
    });

    it("should allow sentinels to create disputes", async function () {
      await market
        .connect(sentinel)
        .createDispute(
          1,
          "Test Dispute",
          "Description",
          Math.floor(Date.now() / 1000),
          Math.floor(Date.now() / 1000) + 3600
        );
      expect((await market.disputes(0)).claimant).to.equal(sentinel.address);
    });

    it("should allow sentinels to commit and reveal votes", async function () {
      const disputeId = 0;
      await market
        .connect(sentinel)
        .createDispute(
          1,
          "Test Dispute",
          "Description",
          Math.floor(Date.now() / 1000),
          Math.floor(Date.now() / 1000) + 3600
        );

      const vote = 1; // YES
      const salt = 1234;
      const commitment = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(["uint8", "uint256"], [vote, salt])
      );
      await market.connect(sentinel).commitVote(disputeId, commitment);

      expect(
        (await market.disputes(disputeId)).commitments(sentinel.address)
      ).to.equal(commitment);

      await ethers.provider.send("evm_increaseTime", [3600]); // Increase time to pass the deadline
      await market.connect(sentinel).revealVote(disputeId, vote, salt);

      expect(
        (await market.disputes(disputeId)).votes(sentinel.address)
      ).to.equal(vote);
    });
  });

  describe("Host Functions", function () {
    it("should allow hosts to register", async function () {
      await market.connect(host).registerHost("multiaddress");
      expect((await market.hosts(host.address)).status).to.equal(1); // ACTIVE
    });

    it("should allow hosts to claim an SFA", async function () {
      // Assume we have a created SFA with id 1
      await token
        .connect(host)
        .approve(market.address, ethers.utils.parseEther("200"));
      await market.connect(host).claimHost(1);
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
          ethers.utils.parseEther("100"),
          Math.floor(Date.now() / 1000) + 3600,
          7200
        );
      await token
        .connect(host)
        .approve(market.address, ethers.utils.parseEther("200"));
      await market.connect(host).claimHost(1);
      await ethers.provider.send("evm_increaseTime", [3600]); // Increase time to pass the start time

      await market.connect(host).claimVesting(1);
      expect(await market.tokenBalances(host.address)).to.be.gt(0);
    });

    it("should allow users to withdraw their balance", async function () {
      await market
        .connect(owner)
        .createSFA(
          "cid",
          ethers.utils.parseEther("100"),
          Math.floor(Date.now() / 1000) + 3600,
          7200
        );
      await token
        .connect(host)
        .approve(market.address, ethers.utils.parseEther("200"));
      await market.connect(host).claimHost(1);
      await ethers.provider.send("evm_increaseTime", [3600]); // Increase time to pass the start time
      await market.connect(host).claimVesting(1);

      const balanceBefore = await token.balanceOf(host.address);
      await market
        .connect(host)
        .withdraw(host.address, ethers.utils.parseEther("10"));
      const balanceAfter = await token.balanceOf(host.address);

      expect(balanceAfter.sub(balanceBefore)).to.equal(
        ethers.utils.parseEther("10")
      );
    });
  });
});
