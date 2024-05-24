//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * to do:
 * [ ] - create or mint new Foward Storage Contract
 * [ ] - take position 
 * [ ] - erc404 functions (transfer, etc etc)
 * 
 * possible struct for Storage Forward Agreement (SFA):
 * creator: address
 * CID string
 * ttl uint
 * price uint 
 * maxHosts uint
 * hosts address[]
 * 
 */
// Uncomment this line to use console.log
// import "hardhat/console.sol";
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Market is ERC721, Ownable {

    uint256 constant BPS_BASE = 10_000

    enum SFAStatus { ACTIVE, INACTIVE, PAUSED, FINISHED }

    struct SFA {
        uint256 cid;
        uint256 vestingCallerIncetiveBPS;
        uint256 vesting;
        uint256 vested;
        uint256 penaltyRatio;
        uint256 penalties;
        uint256 startTime;
        uint256 ttl;
        SFAStatus status;
        address host; 
        address pendingHost;
        uint256 collateral
    }

    struct Host {
        bool active
        uint256 ipfsID
        uint256 pubkey
    }

    mapping(uint256 => SFA) public sfas;
    mapping(address => Host) public hosts;
    mapping(address => bool) public keepers;
    mapping(address => bool) public sentinels;
    uint256 public sfaCounter;
    address public tokenAddress;


    event SFACreated(uint256 indexed sfaId, address indexed publisher, uint256 cid, uint256 vesting, uint256 startTime, uint256 ttl);
    event VestingClaimed(uint256 indexed sfaId, address indexed host, uint256 amount);
    event HostClaimed(uint256 indexed sfaId, address indexed host);
    event HostTransferInitiated(uint256 indexed sfaId, address indexed currentHost, address indexed newHost);
    event HostTransferAccepted(uint256 indexed sfaId, address indexed newHost);

    constructor(address _tokenAddress) ERC721("Storage Forward Agreements", "SFA") {
        tokenAddress = _tokenAddress;
        owner = msg.sender;
    }

    modifier onlyHosts() {
        require(hosts[msg.sender].active, "Not a host");
        _;
    }

    modifier onlyKeepers() {
        require(keepers[msg.sender] || msg.sender == owner, "Not a keeper");
        _;
    }

    modifier onlySentinels() {
        require(sentinel[msg.sender] || msg.sender == owner, "Not a sentinel");
        _;
    }

    function createSFA(
        uint256 _cid,
        uint256 _ttl,
        uint256 _vesting
        uint256 _vestingCallerIncetiveRatio
    ) external {
        require(_vesting > 0, "Vesting amount must be greater than zero");

        uint256 startTime = block.timestamp;

        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), _vesting), "Token transfer failed");

        sfaCounter++;
        _mint(msg.sender, sfaCounter);
        
        sfAs[sfaCounter] = SFA({
            cid: _cid,
            vestingCallerIncetiveRatio: _vestingCallerIncetiveRatio
            vesting: _vesting,
            vested: 0,
            penalties: 0,
            startTime: startTime,
            ttl: _ttl,
            status: SFAStatus.INACTIVE,
            host: address(0),
            pendingHost: address(0)
        });

        emit SFACreated(sfaCounter, msg.sender, _cid, _vesting, startTime, _ttl);
    }

    function claimHost(uint256 _sfaId) external onlyHosts {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(sfa.status == SFAStatus.INACTIVE, "SFA is already active");
        require(sfa.host == address(0), "Host already claimed");

        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this) sfa.collateral), "Token transfer failed");

        sfa.host = msg.sender;
        sfa.status = SFAStatus.ACTIVE;

        emit HostClaimed(_sfaId, msg.sender);
    }

    function initiateHostTransfer(uint256 _sfaId, address _newHost) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(sfa.host == msg.sender, "Only the current host can initiate transfer");
        require(_newHost != address(0), "New host address cannot be zero");

        sfa.pendingHost = _newHost;

        emit HostTransferInitiated(_sfaId, msg.sender, _newHost);
    }

    function acceptHostTransfer(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(sfa.pendingHost == msg.sender, "Only the pending host can accept transfer");

        sfa.host = msg.sender;
        sfa.pendingHost = address(0);

        emit HostTransferAccepted(_sfaId, msg.sender);
    }

    function vestingAvailable(uint256 _sfaId) view returns (uint256 vestingAvailableAmount) {
        SFA storage sfa = sfAs[_sfaId];
        uint256 endTime = sfa.startTime + sfa.ttl
        uint256 elapsedTime = block.timestamp - sfa.startTime;
        uint256 _vestingAvailable = ((elapsedTime * sfa.vesting) / sfa.ttl ) - sfa.vested;
        uint256 vestingAvailableAmount = _vestingAvailable > sfa.vesting ? sfa.vesting : _vestingAvailable;
        return vestingAvailableAmount
    }

    function vestingCallerIncentives(uint256 _sfaId) view returns (uint256 vestingCallerIncentivesAmount) {
        SFA storage sfa = sfAs[_sfaId];
        uint256 endTime = sfa.startTime + sfa.ttl
        uint256 elapsedTime = block.timestamp - sfa.startTime;
        uint256 _vestingAvailable = ((elapsedTime * sfa.vesting) / sfa.ttl ) - sfa.vested;
        uint256 vestingAvailable = _vestingAvailable > sfa.vesting ? sfa.vesting : _vestingAvailable;
        uint256 vestingCallerIncentivesAmount =  vestingAvailable * sfa.vestingCallerIncetiveBPS / BPS_BASE
        return vestingCallerIncentivesAmount
    }

    function claimVesting(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(sfa.status != SFAStatus.INACTIVE && sfa.status != SFAStatus.PAUSED, "SFA is not active");
        require(sfa.host == msg.sender, "Only the host can claim vesting");
        require(block.timestamp > sfa.startTime, "Vesting period has not started yet");

        uint256 _vestingAvailable = vestingAvailable(_sfaId)
        require(_vestingAvailable > 0, "No vested tokens available");
        uint256 _callerIncentives =  _vestingAvailable * sfa.vestingCallerIncetiveBPS / BPS_BASE
        sfa.vested += _vestingAvailable;
        require(IERC20(tokenAddress).transfer(sfa.host, _vestingAvailable), "Token transfer failed");
        require(IERC20(tokenAddress).transfer(msg.sender, _callerIncentives), "Token transfer failed");

        if (sfa.status != SFAStatus.FINISHED && (sfa.startTime + sfa.ttl) > block.timestamp) {
            sfa.status SFAStatus.FINISHED
        }

        emit VestingClaimed(_sfaId, msg.sender, _vestingAvailable);
    }

    function claimCollateral(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(sfa.status == SFAStatus.FINISHED , "SFA is not finished");
        require(sfa.host == msg.sender, "Only the host can claim vesting");
        require(block.timestamp > sfa.startTime, "Vesting period has not started yet");

        uint256 _vestingAvailable = vestingAvailable(_sfaId)
        require(_vestingAvailable > 0, "No vested tokens available");
        sfa.vested += _vestingAvailable;
        require(IERC20(tokenAddress).transfer(msg.sender, _vestingAvailable), "Token transfer failed");

        if (sfa.status != SFAStatus.FINISHED && (sfa.startTime + sfa.ttl) > block.timestamp) {
            sfa.status SFAStatus.FINISHED
        }

        emit VestingClaimed(_sfaId, msg.sender, _vestingAvailable);
    }
}
