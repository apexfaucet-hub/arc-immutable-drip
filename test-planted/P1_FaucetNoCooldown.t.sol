// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FaucetNoCooldown} from "planted/FaucetNoCooldown.sol";
import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {FaucetSpec} from "contracts/test/spec/FaucetSpec.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev P1: the SAME FaucetSpec, with only the faucet hook pointing at the faulty copy.
contract P1_FaucetNoCooldownTest is RealHooks, FaucetSpec {
    function _newFaucet(IERC20 token, uint256 claimAmount, uint64 cooldown)
        internal
        override(RealHooks, SpecBase)
        returns (IDripFaucet)
    {
        return IDripFaucet(address(new FaucetNoCooldown(token, claimAmount, cooldown)));
    }
}
