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

    struct Host {
        Status status;
        string peerID;
        string pubkey;
    }

    struct Sentinel {
        Status status;
        uint256 collateral;
    }

    mapping(address => uint256) public tokenBalances;
    mapping(address => bool) public withdrawalPaused;
    mapping(address => uint256) public penalties;
    mapping(uint256 => SFA) public sfas;
    mapping(address => Host) public hosts;
    mapping(address => bool) public keepers;
    mapping(address => Sentinel) public sentinels;

    uint256 public sfaCounter;
    uint256 public callerIncentivesBPS;
    uint256 public sfaCollateralRatioBPS;
    uint256 public sentinelsCollateral;
    uint256 public sentinelFeeBPS;
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
    event Withdrawed(address indexed from, address indexed to, uint256 amount);
    event Panic(bool panic);

    constructor(address _tokenAddress) ERC721("Storage Forward Agreements", "SFA Market") Ownable() {
        tokenAddress = _tokenAddress;
        callerIncentivesBPS = 50;
        sfaCollateralRatioBPS = 20_000;
    }

    /**
     * Modifiers
     */

    modifier onlyHosts() {
        require(hosts[msg.sender].active, "Not a host");
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

    function createSFA(string memory _cid, uint256 _ttl, uint256 _vesting) external {
        require(_vesting > 0, "Vesting amount must be greater than zero");
        uint256 startTime = block.timestamp;
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), _vesting), "Token transfer failed");
        sfaCounter++;
        _mint(msg.sender, sfaCounter);
        sfas[sfaCounter] = SFA({
            publisher: msg.sender,
            cid: _cid,
            vesting: _vesting,
            vested: 0,
            collateral: (_vesting * sfaCollateralRatioBPS) / BPS_BASE,
            startTime: startTime,
            ttl: _ttl,
            status: Status.INACTIVE,
            host: address(0),
            pendingHost: address(0)
        });
        emit SFACreated(sfaCounter, msg.sender, _cid, _vesting, startTime, _ttl);
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

    function updateSFAStatus(uint256 _sfaId, SFAStatus _newStatus) external onlyKeepers {
        require(_newStatus == Status.ACTIVE || _newStatus == Status.PAUSED, "New Status is not ACTIVE or PAUSED");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.status == Status.ACTIVE || sfa.status == Status.PAUSED, "SFA Status is not ACTIVE or PAUSED");
        sfa.status = _newStatus
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
        sentinels[sentinel] = false;
    }

    /**
     * Sentinel Funcs
     */

    function registerSentinel() external {
        require(!panic);
        require(sentinels[msg.sender].status != Status.INACTIVE, "Sentinel already registered");
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), sentinelsCollateral), "Token transfer failed");
        sentinels[msg.sender] = Sentinel({status: Status.ACTIVE, collateral: sentinelsCollateral});
    }

    function reportDowntime(uint256 _sfaId, uint256 time) external onlySentinels {
        require(!panic, "Panic!");
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.status == Status.ACTIVE, "SFA is not active");
        uint256 penalty = (time * sfa.vesting * sfaCollateralRatioBPS) / BPS_BASE / sfa.ttl;
        sfa.collateral -= penalty;
        uint256 fee = (penalty * sentinelFeeBPS) / BPS_BASE;
        tokenBalances[msg.sender] += fee;
        tokenBalances[sfa.publisher] += penalty - fee;
    }

    /**
     * Host Funcs
     */

    function registerHost(string memory _peerID, string memory _pubkey) external {
        require(!hosts[msg.sender].active, "Host already registered");
        hosts[msg.sender] = Host({active: true, peerID: _peerID, pubkey: _pubkey});
    }

    function updateHost(string memory _peerID, string memory _pubkey) external {
        require(hosts[msg.sender].active, "Host not registered");
        hosts[msg.sender].peerID = _peerID;
        hosts[msg.sender].pubkey = _pubkey;
    }

    function claimHost(uint256 _sfaId) external onlyHosts {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.status == Status.INACTIVE, "SFA is already active");
        require(sfa.host == address(0), "Host already claimed");
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), sfa.collateral), "Token transfer failed");
        sfa.host = msg.sender;
        sfa.status = Status.ACTIVE;
    }

    function initiateHostTransfer(uint256 _sfaId, address _newHost) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.host == msg.sender, "Only the current host can initiate transfer");
        require(_newHost != address(0), "New host address cannot be zero");
        sfa.pendingHost = _newHost;
    }

    function acceptHostTransfer(uint256 _sfaId) external {
        require(!panic, "Panic!");
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
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
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
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
        uint256 balanceAvailable = tokenBalances[msg.sender] - penalties[msg.sender];
        require(balanceAvailable > _amount, "Insufficiente Token balance");
        tokenBalances[msg.sender] -= _amount;
        penalties[msg.sender] = 0;
        require(IERC20(tokenAddress).transfer(_to, _amount), "Token transfer failed");
    }
}
