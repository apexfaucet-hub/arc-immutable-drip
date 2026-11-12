// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {ITokenReceiverHook} from "contracts/test/mocks/HookToken.sol";

/// @dev Test-only attacker: inside the token hook it re-enters `claim()` with the SAME msg.sender
/// (this contract) as the outer claim.
contract ClaimAttacker is ITokenReceiverHook {
    IDripFaucet public immutable faucet;
    bool public bubble;
    uint256 public hookCalls;
    bool public reentryAttempted;
    bool public reentryOk;
    bytes public reentryRet;

    constructor(IDripFaucet faucet_) {
        faucet = faucet_;
    }

    function attack(bool bubble_) external {
        bubble = bubble_;
        faucet.claim();
    }

    function onTokenReceived(address, uint256) external {
        hookCalls += 1;
        if (hookCalls != 1) return; // only re-enter once, from the outer claim's hook
        reentryAttempted = true;
        if (bubble) {
            faucet.claim();
            reentryOk = true;
        } else {
            try faucet.claim() returns (uint256) {
                reentryOk = true;
            } catch (bytes memory reason) {
                reentryRet = reason;
            }
        }
    }
}
