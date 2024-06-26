// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SFAToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Storage Forward Agreement Token", "SFAT") {
        _mint(msg.sender, initialSupply);
    }
}
