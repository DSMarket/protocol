//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * to do:
 * [X] - hosts funcs
 * [x] - owner funcs
 * [x] - keeper funcs
 * [x] - sentinels funcs
 * [x] - balance funcs
 * [x] - add require for "panic" in many funcs
 * [WIP] - adding disputes (missing adding how manage balance for rewards and penalties in dispute)
 * [ ] - add DAO fees
 * [ ] - add sentinels funcs when want to udpate status or retire as nodes
 *
 * to Improve how ERC20 balance is manage in local and avoid that user spend gas on frecuenly call IERC20 transfer.
 * decide to use a "local balance" where internal will charge and later if address want to withdraw can call "withdraw" to transfer their balance to somewhere
 * I was thinking that collateral penalties can be a mapping of balance where we can charge address that can later can transfered.
 *
 * Owner can:
 * - change "caller incentives BPS"
 * - change "penalty BPS"
 * - change "keepers"
 * - all keeper actions
 * - all sentinel actions
 *
 * Keepers can:
 * - pause a SFA
 * - pause pause withdraw for one address or for all (emergency stop)
 * - kick sentinel out (and pause their funds)
 *
 * Sentinels can:
 * - report downtime of CID in host, asking for penalties (here we need to apply a better logic of how validate sentinel behavior)
 */

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Market is ERC721, Ownable {
    uint256 constant BPS_BASE = 10_000;

    enum Vote {
        NONE,
        YES,
        NO,
        ABSTAIN
    }

    enum Status {
        INACTIVE,
        ACTIVE,
        PAUSED,
        FINISHED
    }

    struct SFA {
        address publisher;
        string cid;
        uint256 vesting;
        uint256 vested;
        uint256 startTime;
        uint256 ttl;
        Status status;
        address host;
        address pendingHost;
        uint256 collateral;
    }

    struct Dispute {
        address claimant;
        uint256 sfaId;
        string title;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 deadline;
        uint256 penalties;
        mapping(address => bytes32) commitments;
        mapping(address => Vote) votes;
        address[] arbitrators;
        Status status;
    }

    struct Host {
        Status status;
        string multiaddress;
    }

    struct Sentinel {
        Status status;
        uint256 collateral;
    }

    mapping(address => uint256) public disputeBalances;
    mapping(address => uint256) public tokenBalances;
    mapping(uint256 => SFA) public sfas;
    mapping(address => Host) public hosts;
    mapping(address => Sentinel) public sentinels;
    mapping(uint256 => address) public sentinelsIndex;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => bool) public withdrawalPaused;
    mapping(address => bool) public keepers;

    uint256 public sentinelsCounter;
    uint256 public disputeCounter;
    uint256 public sfaCounter;
    uint256 public callerIncentivesBPS = 50;
    uint256 public sentinelFeeBPS = 50;
    uint256 public sfaCollateralRatioBPS = 20_000;
    uint256 public sentinelsCollateral = 30e18;
    uint256 public arbitratorsPerDispute = 3;
    address public tokenAddress;
    bool public panic;

    event SFACreated(
        uint256 indexed sfaId,
        address indexed publisher,
        string cid,
        uint256 vesting,
        uint256 startTime,
        uint256 ttl
    );
    event DisputeCreated(uint256 sfaId, address claimant, string title, string description);
    event ArbitratorsSelected(uint256 disputeId, address[] selectedArbitrators);
    event DisputeResolved(uint256 disputeId, Vote result);
    event Withdrawed(address indexed from, address indexed to, uint256 amount);
    event Panic(bool panic);

    constructor(address _tokenAddress) ERC721("Storage Forward Agreements", "SFA Market") Ownable() {
        tokenAddress = _tokenAddress;
    }

    /**
     * Modifiers
     */

    modifier onlyHosts() {
        require(hosts[msg.sender].status == Status.ACTIVE, "Not a host");
        _;
    }

    modifier onlyKeepers() {
        require(keepers[msg.sender] || msg.sender == owner(), "Not a keeper");
        _;
    }

    modifier onlySentinels() {
        require(sentinels[msg.sender].status == Status.ACTIVE || msg.sender == owner(), "Not a sentinel");
        _;
    }

    function createSFA(string memory _cid, uint256 _vesting, uint256 _startTime, uint256 _ttl) external {
        require(_vesting > 0, "Vesting amount must be greater than zero");
        require(_startTime > block.timestamp, "Start time must be older than block timestamp");
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), _vesting), "Token transfer failed");
        sfaCounter++;
        _mint(msg.sender, sfaCounter);
        sfas[sfaCounter] = SFA({
            publisher: msg.sender,
            cid: _cid,
            vesting: _vesting,
            vested: 0,
            collateral: (_vesting * sfaCollateralRatioBPS) / BPS_BASE,
            startTime: _startTime,
            ttl: _ttl,
            status: Status.INACTIVE,
            host: address(0),
            pendingHost: address(0)
        });
        emit SFACreated(sfaCounter, msg.sender, _cid, _vesting, _startTime, _ttl);
    }

    /**
     * Owner Funcs
     */

    function setKeeper(address _keeper, bool _status) external onlyOwner {
        keepers[_keeper] = _status;
    }

    function updateSentinelStatus(address _sentinel, Status _newStatus) external onlyOwner {
        sentinels[_sentinel].status = _newStatus;
    }

    function setCallerIncentivesBPS(uint256 _newBPS) external onlyOwner {
        require(_newBPS <= BPS_BASE, "BPS value cannot exceed 10000");
        callerIncentivesBPS = _newBPS;
    }

    function setCollateralRatioBPS(uint256 _newBPS) external onlyOwner {
        require(_newBPS <= BPS_BASE, "BPS value cannot exceed 10000");
        sfaCollateralRatioBPS = _newBPS;
    }

    /**
     * Keepers Funcs
     */

    function updateSFAStatus(uint256 _sfaId, Status _newStatus) external onlyKeepers {
        require(_newStatus == Status.ACTIVE || _newStatus == Status.PAUSED, "New Status is not ACTIVE or PAUSED");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.status == Status.ACTIVE || sfa.status == Status.PAUSED, "SFA Status is not ACTIVE or PAUSED");
        sfa.status = _newStatus;
    }

    function setPauseWithdrawals(address _user, bool _bool) external onlyKeepers {
        withdrawalPaused[_user] = _bool;
    }

    function setPanic(bool _bool) external onlyKeepers {
        panic = _bool;
        emit Panic(_bool);
    }

    function kickSentinel(address sentinel) external onlyKeepers {
        withdrawalPaused[sentinel] = true;
        sentinels[sentinel].status = Status.PAUSED;
    }

    /**
     * Sentinels Funcs
     */

    function registerSentinel() external {
        require(!panic);
        require(sentinels[msg.sender].status != Status.INACTIVE, "Sentinel already registered");
        require(
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), sentinelsCollateral),
            "Token transfer failed"
        );
        sentinels[msg.sender] = Sentinel({status: Status.ACTIVE, collateral: sentinelsCollateral});
    }

    function createDispute(
        uint256 _sfaId,
        string memory _title,
        string memory _description,
        uint256 _startTime,
        uint256 _endTime
    ) external onlySentinels {
        Dispute storage dispute = disputes[disputeCounter];
        dispute.claimant = msg.sender;
        dispute.sfaId = _sfaId;
        dispute.title = _title;
        dispute.startTime = _startTime;
        dispute.endTime = _endTime;
        dispute.description = _description;
        dispute.status = Status.ACTIVE;
        dispute.deadline = block.timestamp + 1 hours;

        uint256 i = 0;
        uint256 randomNumber = block.prevrandao;
        while (dispute.arbitrators.length < arbitratorsPerDispute) {
            uint256 randomIndex = (randomNumber >> (i * 15)) & 0xFFFF % sentinelsCounter;
            address selectedSentinel = sentinelsIndex[randomIndex];
            if (sentinels[selectedSentinel].status == Status.ACTIVE) {
                dispute.arbitrators.push(selectedSentinel);
            }
            i++;
        }

        emit DisputeCreated(disputeCounter, msg.sender, _title, _description);
        emit ArbitratorsSelected(disputeCounter, dispute.arbitrators);
        disputeCounter++;
    }

    function commitVote(uint256 _disputeId, bytes32 _commitment) external onlySentinels {
        require(isSelectedArbitrator(_disputeId, msg.sender), "Not a selected arbitrator");
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == Status.ACTIVE, "Dispute No Active");
        require(dispute.deadline > block.timestamp, "Deadline Finnished");
        require(dispute.commitments[msg.sender] == 0, "Already voted");
        dispute.commitments[msg.sender] = _commitment;
    }

    function revealVote(uint256 _disputeId, Vote _vote, uint256 _salt) external onlySentinels {
        require(isSelectedArbitrator(_disputeId, msg.sender), "Not a selected arbitrator");
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == Status.ACTIVE, "Dispute No Active");
        require(dispute.deadline < block.timestamp, "Commit Deadline not Finnished");
        require((dispute.deadline + 1 hours) > block.timestamp, "Deadline Finnished");
        bytes32 commitment = keccak256(abi.encodePacked(_vote, _salt));
        require(disputes[_disputeId].commitments[msg.sender] == commitment, "Invalid reveal");
        disputes[_disputeId].votes[msg.sender] = _vote;
    }

    function resolveDispute(uint256 _disputeId) external onlySentinels {
        Dispute storage dispute = disputes[_disputeId];
        require((dispute.deadline + 1 hours) < block.timestamp, "Deadline not end");
        require(dispute.status == Status.ACTIVE, "Dispute finished");

        uint256 yesCount = 0;
        uint256 noCount = 0;
        uint256 abstainCount = 0;

        for (uint256 i = 0; i < dispute.arbitrators.length; i++) {
            address arbitrator = dispute.arbitrators[i];
            Vote vote = dispute.votes[arbitrator];
            if (vote == Vote.YES) {
                yesCount++;
            } else if (vote == Vote.NO) {
                noCount++;
            } else if (vote == Vote.ABSTAIN) {
                abstainCount++;
            }
        }

        Vote result = yesCount > noCount ? Vote.YES : Vote.NO;
        dispute.status = Status.FINISHED;

        if (result == Vote.YES) {
            uint256 reward = 0;
            reward = (sfas[dispute.sfaId].collateral * sentinelFeeBPS) / BPS_BASE;
            sfas[dispute.sfaId].collateral -= reward;
            tokenBalances[dispute.claimant] += reward;
        }

        emit DisputeResolved(_disputeId, result);
    }

    function isSelectedArbitrator(uint256 _disputeId, address _arbitrator) internal view returns (bool) {
        for (uint256 i = 0; i < disputes[_disputeId].arbitrators.length; i++) {
            if (disputes[_disputeId].arbitrators[i] == _arbitrator) {
                return true;
            }
        }
        return false;
    }

    /**
     * Host Funcs
     */

    function registerHost(string memory _multiaddress) external {
        require(hosts[msg.sender].status == Status.INACTIVE, "Host already registered");
        hosts[msg.sender] = Host({status: Status.ACTIVE, multiaddress: _multiaddress});
    }

    function updateHost(string memory _multiaddress) external {
        require(hosts[msg.sender].status != Status.INACTIVE, "Host not registered");
        hosts[msg.sender].multiaddress = _multiaddress;
    }

    function claimHost(uint256 _sfaId) external onlyHosts {
        SFA storage sfa = sfas[_sfaId];
        require(sfa.startTime != 0, "SFA does not exist");
        require(sfa.status == Status.INACTIVE, "SFA is already active");
        require(sfa.host == address(0), "Host already claimed");
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), sfa.collateral), "Token transfer failed");
        sfa.host = msg.sender;
        sfa.status = Status.ACTIVE;
    }

    function initiateHostTransfer(uint256 _sfaId, address _newHost) external {
        SFA storage sfa = sfas[_sfaId];
        require(sfa.startTime != 0, "SFA does not exist");
        require(sfa.host == msg.sender, "Only the current host can initiate transfer");
        require(_newHost != address(0), "New host address cannot be zero");
        sfa.pendingHost = _newHost;
    }

    function acceptHostTransfer(uint256 _sfaId) external {
        require(!panic, "Panic!");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.startTime != 0, "SFA does not exist");
        require(sfa.pendingHost == msg.sender, "Only the pending host can accept transfer");
        sfa.host = msg.sender;
        sfa.pendingHost = address(0);
    }

    /**
     * Vesting Func
     */

    function vestingAvailable(uint256 _sfaId) public view returns (uint256 vestingAvailableAmount) {
        SFA storage sfa = sfas[_sfaId];
        uint256 elapsedTime = block.timestamp - sfa.startTime;
        uint256 _vestingAvailable = (elapsedTime * sfa.vesting) / sfa.ttl;
        uint256 __vestingAvailable = _vestingAvailable > sfa.vesting ? sfa.vesting : _vestingAvailable;
        vestingAvailableAmount = sfa.vested > __vestingAvailable ? 0 : (__vestingAvailable - sfa.vested);
        return vestingAvailableAmount;
    }

    function vestingCallerIncentives(uint256 _sfaId) public view returns (uint256 vestingCallerIncentivesAmount) {
        uint256 _vestingAvailable = vestingAvailable(_sfaId);
        vestingCallerIncentivesAmount = (_vestingAvailable * callerIncentivesBPS) / BPS_BASE;
        return vestingCallerIncentivesAmount;
    }

    function claimVesting(uint256 _sfaId) external {
        require(!panic, "Panic!");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.startTime != 0, "SFA does not exist");
        require(sfa.status == Status.ACTIVE, "SFA is not active");
        require(sfa.host == msg.sender, "Only the host can claim vesting");
        require(block.timestamp > sfa.startTime, "Vesting period has not started yet");
        uint256 _vestingAvailable = vestingAvailable(_sfaId);
        require(_vestingAvailable > 0, "No vested tokens available");
        uint256 _callerIncentives = (_vestingAvailable * callerIncentivesBPS) / BPS_BASE;
        sfa.vested += _vestingAvailable;
        tokenBalances[sfa.host] += _vestingAvailable;
        tokenBalances[msg.sender] += _callerIncentives;

        if (sfa.status != Status.FINISHED && (sfa.startTime + sfa.ttl) > block.timestamp) {
            sfa.status = Status.FINISHED;
            tokenBalances[sfa.host] += sfa.collateral;
        }
    }

    /**
     * Withdraw Balance
     */
    function withdraw(address _to, uint256 _amount) external {
        require(!panic, "Panic!");
        require(tokenBalances[msg.sender] > _amount, "Insufficiente Token balance");
        tokenBalances[msg.sender] -= _amount;
        require(IERC20(tokenAddress).transfer(_to, _amount), "Token transfer failed");
    }
}
