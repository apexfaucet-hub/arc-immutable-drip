// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FaucetReentrant} from "planted/FaucetReentrant.sol";
import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {FaucetSpec} from "contracts/test/spec/FaucetSpec.sol";
import {ReentrancySpec} from "contracts/test/spec/ReentrancySpec.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev P5: the SAME FaucetSpec, with only the faucet hook pointing at the faulty copy.
/// Ordinary faucet behaviour is unaffected, so every test here is expected to PASS.
contract P5_FaucetReentrant_FaucetSpecTest is RealHooks, FaucetSpec {
    function _newFaucet(IERC20 token, uint256 claimAmount, uint64 cooldown)
        internal
        override(RealHooks, SpecBase)
        returns (IDripFaucet)
    {
        return IDripFaucet(address(new FaucetReentrant(token, claimAmount, cooldown)));
    }
}

/// @dev P5: the SAME ReentrancySpec, with only the faucet hook pointing at the faulty copy.
/// The two claim re-entry tests must FAIL; the drip and launch re-entry tests (production vault and
/// launchpad) must still PASS.
contract P5_FaucetReentrant_ReentrancySpecTest is RealHooks, ReentrancySpec {
    function _newFaucet(IERC20 token, uint256 claimAmount, uint64 cooldown)
        internal
        override(RealHooks, SpecBase)
        returns (IDripFaucet)
    {
        return IDripFaucet(address(new FaucetReentrant(token, claimAmount, cooldown)));
    }
}
