// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Neutral demo token for the drip launchpad: 18 decimals, fixed supply minted once to the
/// deployer in the constructor. No mint function, no owner.
contract DripDemoToken is ERC20 {
    constructor(uint256 supply) ERC20("Drip Demo Token", "DRIPDEMO") {
        _mint(msg.sender, supply);
    }
}
