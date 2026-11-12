// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test-only USDC-style token with a blocklist: any transfer from or to a blocked address reverts.
contract BlocklistToken is ERC20 {
    error Blocked(address account);

    mapping(address => bool) public blocked;

    constructor() ERC20("Blocklist", "BLK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlocked(address account, bool value) external {
        blocked[account] = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (blocked[from]) revert Blocked(from);
        if (blocked[to]) revert Blocked(to);
        super._update(from, to, value);
    }
}
