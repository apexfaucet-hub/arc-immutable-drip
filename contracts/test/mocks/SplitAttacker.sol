// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {ITokenReceiverHook} from "contracts/test/mocks/HookToken.sol";

/// @dev Test-only payee contract: inside the token hook of its own `withdraw` it re-enters the split
/// with `withdraw` (mode 0) or `release` (mode 1), either catching or bubbling the failure.
contract SplitAttacker is ITokenReceiverHook {
    ISplit public split;
    IERC20 public token;
    uint8 public mode;
    bool public bubble;
    uint256 public hookCalls;
    bool public reentryAttempted;
    bool public reentryOk;
    bytes public reentryRet;

    function setUp(ISplit split_, IERC20 token_) external {
        split = split_;
        token = token_;
    }

    function attack(uint8 mode_, bool bubble_) external {
        mode = mode_;
        bubble = bubble_;
        split.withdraw(token);
    }

    function onTokenReceived(address, uint256) external {
        hookCalls += 1;
        if (hookCalls != 1) return;
        reentryAttempted = true;
        if (bubble) {
            _reenter();
            reentryOk = true;
        } else {
            try this.reenterExternal() {
                reentryOk = true;
            } catch (bytes memory reason) {
                reentryRet = reason;
            }
        }
    }

    function reenterExternal() external {
        require(msg.sender == address(this), "self only");
        _reenter();
    }

    function _reenter() private {
        if (mode == 0) split.withdraw(token);
        else split.release(token);
    }
}
