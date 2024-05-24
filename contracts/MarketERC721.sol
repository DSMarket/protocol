//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * to do:
 * [ ] - hosts funcs
 * [ ] - keeper funcs
 * [ ] - sentinels funcs
 * [ ] - collateral funcs
 * [x] - balance funcs
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
 * 
 * Sentinels can:
 * - report downtime of CID in host, asking for penalties
 */

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Market is ERC721, Ownable {

    uint256 constant BPS_BASE = 10_000;

    enum SFAStatus { ACTIVE, INACTIVE, PAUSED, FINISHED }

    struct SFA {
        string cid;
        uint256 vesting;
        uint256 vested;
        uint256 startTime;
        uint256 ttl;
        SFAStatus status;
        address host; 
        address pendingHost;
        uint256 collateral;
    }

    struct Host {
        bool active;
        string peerID;
        string pubkey;
    }

    mapping(address => uint256) public tokenBalances;
    mapping(address => uint256) public penalties;
    mapping(uint256 => SFA) public sfas;
    mapping(address => Host) public hosts;
    mapping(address => bool) public keepers;
    mapping(address => bool) public sentinels;

    uint256 public sfaCounter;
    uint256 public callerIncentivesBPS;
    uint256 public penaltyBPS;
    address public tokenAddress;


    event SFACreated(uint256 indexed sfaId, address indexed publisher, string cid, uint256 vesting, uint256 startTime, uint256 ttl);
    event VestingClaimed(uint256 indexed sfaId, address indexed host, uint256 amount);
    event Withdrawed(address indexed from, address indexed to, uint256 amount);
    event HostClaimed(uint256 indexed sfaId, address indexed host);
    event HostTransferInitiated(uint256 indexed sfaId, address indexed currentHost, address indexed newHost);
    event HostTransferAccepted(uint256 indexed sfaId, address indexed newHost);

    constructor(address _tokenAddress) ERC721("Storage Forward Agreements", "SFA Market") Ownable() {
        tokenAddress = _tokenAddress;
        callerIncentivesBPS = 50;
        penaltyBPS = 20_000;
    }

    modifier onlyHosts() {
        require(hosts[msg.sender].active, "Not a host");
        _;
    }

    modifier onlyKeepers() {
        require(keepers[msg.sender] || msg.sender == owner(), "Not a keeper");
        _;
    }

    modifier onlySentinels() {
        require(sentinels[msg.sender] || msg.sender == owner(), "Not a sentinel");
        _;
    }

    function createSFA(
        string memory _cid,
        uint256 _ttl,
        uint256 _vesting,
        uint256 _collateralRatio
    ) external {
        require(_vesting > 0, "Vesting amount must be greater than zero");

        uint256 startTime = block.timestamp;

        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), _vesting), "Token transfer failed");

        sfaCounter++;
        _mint(msg.sender, sfaCounter);
        
        sfas[sfaCounter] = SFA({
            cid: _cid,
            vesting: _vesting,
            vested: 0,
            collateral: _vesting * _collateralRatio,
            startTime: startTime,
            ttl: _ttl,
            status: SFAStatus.INACTIVE,
            host: address(0),
            pendingHost: address(0)
        });

        emit SFACreated(sfaCounter, msg.sender, _cid, _vesting, startTime, _ttl);
    }

    /**
     * Host Funcs
     */

    function claimHost(uint256 _sfaId) external onlyHosts {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.status == SFAStatus.INACTIVE, "SFA is already active");
        require(sfa.host == address(0), "Host already claimed");

        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), sfa.collateral), "Token transfer failed");

        sfa.host = msg.sender;
        sfa.status = SFAStatus.ACTIVE;

        emit HostClaimed(_sfaId, msg.sender);
    }

    function initiateHostTransfer(uint256 _sfaId, address _newHost) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.host == msg.sender, "Only the current host can initiate transfer");
        require(_newHost != address(0), "New host address cannot be zero");

        sfa.pendingHost = _newHost;

        emit HostTransferInitiated(_sfaId, msg.sender, _newHost);
    }

    function acceptHostTransfer(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.pendingHost == msg.sender, "Only the pending host can accept transfer");

        sfa.host = msg.sender;
        sfa.pendingHost = address(0);

        emit HostTransferAccepted(_sfaId, msg.sender);
    }

    /**
     * Vesting Func
     */

    function vestingAvailable(uint256 _sfaId) public view returns (uint256 vestingAvailableAmount) {
        SFA storage sfa = sfas[_sfaId];
        uint256 elapsedTime = block.timestamp - sfa.startTime;
        uint256 _vestingAvailable = (elapsedTime * sfa.vesting) / sfa.ttl;
        uint256 __vestingAvailable = _vestingAvailable > sfa.vesting ? sfa.vesting : _vestingAvailable;
        vestingAvailableAmount = sfa.vested > __vestingAvailable ? 0 : ( __vestingAvailable - sfa.vested );
        return vestingAvailableAmount;
    }

    function vestingCallerIncentives(uint256 _sfaId) public view returns (uint256 vestingCallerIncentivesAmount) {
        uint256 _vestingAvailable = vestingAvailable(_sfaId);
        vestingCallerIncentivesAmount =  _vestingAvailable * callerIncentivesBPS / BPS_BASE;
        return vestingCallerIncentivesAmount;
    }

    function claimVesting(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfas[_sfaId];
        require(sfa.status == SFAStatus.ACTIVE, "SFA is not active");
        require(sfa.host == msg.sender, "Only the host can claim vesting");
        require(block.timestamp > sfa.startTime, "Vesting period has not started yet");

        uint256 _vestingAvailable = vestingAvailable(_sfaId);
        require(_vestingAvailable > 0, "No vested tokens available");
        uint256 _callerIncentives =  _vestingAvailable * callerIncentivesBPS / BPS_BASE;
        sfa.vested += _vestingAvailable;
        tokenBalances[sfa.host] += _vestingAvailable;
        tokenBalances[msg.sender] += _callerIncentives;

        if (sfa.status != SFAStatus.FINISHED && (sfa.startTime + sfa.ttl) > block.timestamp) {
            sfa.status = SFAStatus.FINISHED;
            tokenBalances[sfa.host] += sfa.collateral;
        }

        emit VestingClaimed(_sfaId, msg.sender, _vestingAvailable);
    }

    /**
     * Withdraw Balance
     */
    function withdraw(address _to, uint256 _amount ) external {
        uint256 balanceAvailable = tokenBalances[msg.sender] - penalties[msg.sender];
        require(balanceAvailable > _amount, "Insufficiente Token balance");
        tokenBalances[msg.sender] -= _amount;
        penalties[msg.sender] = 0;
        require(IERC20(tokenAddress).transfer(_to, _amount), "Token transfer failed");
        emit Withdrawed(msg.sender, _to, balanceAvailable);
    }

}
