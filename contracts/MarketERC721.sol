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
    enum SFAStatus { ACTIVE, INACTIVE, PAUSED, FINISHED }

    struct SFA {
        uint256 cid;
        uint256 price; // in tokens
        uint256 vesting; // total tokens to be vested
        uint256 startTime; // timestamp of the start
        uint256 ttl; // Time To Live in seconds
        SFAStatus status; // status of the SFA
        address host; // address of the host
        address pendingHost; // address of the pending host
    }

    struct Host {
        uint256 ipfsID
        uint256 pubkey
    }

    mapping(uint256 => SFA) public sfas;
    mapping(address => Host) public hosts;
    mapping(address => bool) public keepers;
    mapping(address => bool) public sentinels;
    uint256 public sfaCounter;
    address public tokenAddress; // address of the token used for payments


    event SFACreated(uint256 indexed sfaId, address indexed publisher, uint256 cid, uint256 vesting, uint256 startTime, uint256 ttl);
    event VestingClaimed(uint256 indexed sfaId, address indexed host, uint256 amount);
    event HostClaimed(uint256 indexed sfaId, address indexed host);
    event HostTransferInitiated(uint256 indexed sfaId, address indexed currentHost, address indexed newHost);
    event HostTransferAccepted(uint256 indexed sfaId, address indexed newHost);

    constructor(address _tokenAddress) ERC721("Storage Forward Agreement", "SFA") {
        tokenAddress = _tokenAddress;
        owner = msg.sender;
    }

    modifier onlyKeepers() {
        require(keepers[msg.sender] || msg.sender == owner, "Not the keeper");
        _;
    }

    modifier onlySentinels() {
        require(sentinel[msg.sender] || msg.sender == owner, "Not the sentinel");
        _;
    }

    function createSFA(
        uint256 _cid,
        uint256 _price,
        uint256 _ttl,
        uint256 _vesting
    ) external {
        require(_vesting > 0, "Vesting amount must be greater than zero");

        uint256 startTime = block.timestamp;

        // Transfer tokens from the publisher to the contract
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), _vesting), "Token transfer failed");

        sfaCounter++;
        _mint(msg.sender, sfaCounter);
        
        sfAs[sfaCounter] = SFA({
            cid: _cid,
            price: _price,
            vesting: _vesting,
            startTime: startTime,
            ttl: _ttl,
            active: false,
            host: address(0),
            pendingHost: address(0)
        });

        emit SFACreated(sfaCounter, msg.sender, _cid, _vesting, startTime, _ttl);
    }

    function claimHost(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(!sfa.active, "SFA is already active");
        require(sfa.host == address(0), "Host already claimed");

        sfa.host = msg.sender;
        sfa.active = true;

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

    function claimVesting(uint256 _sfaId) external {
        require(_exists(_sfaId), "SFA does not exist");
        SFA storage sfa = sfAs[_sfaId];
        require(sfa.active, "SFA is not active");
        require(sfa.host == msg.sender, "Only the host can claim vesting");
        require(block.timestamp > sfa.startTime, "Vesting period has not started yet");
        
        uint256 elapsedTime = block.timestamp - sfa.startTime;
        uint256 vestedAmount = (elapsedTime * sfa.vesting) / sfa.ttl;

        require(vestedAmount > 0, "No vested tokens available");

        uint256 claimableAmount = vestedAmount > sfa.vesting ? sfa.vesting : vestedAmount;

        require(IERC20(tokenAddress).transfer(msg.sender, claimableAmount), "Token transfer failed");

        sfa.vesting -= claimableAmount;

        if (sfa.vesting == 0) {
            sfa.active = false;
        }

        emit VestingClaimed(_sfaId, msg.sender, claimableAmount);
    }
}
