// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ITokenReceiverHook {
    function onTokenReceived(address from, uint256 amount) external;
}

/// @dev Test-only ERC-777 style token: after every transfer (not mint) it calls `onTokenReceived`
/// on the recipient when the recipient is a contract.
contract HookToken is ERC20 {
    constructor() ERC20("Hook", "HOOK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0) && to != address(0) && to.code.length > 0) {
            ITokenReceiverHook(to).onTokenReceived(from, value);
        }
    }
}
