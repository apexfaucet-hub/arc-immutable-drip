// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VaultNoPeriod} from "planted/VaultNoPeriod.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {VaultSpec} from "contracts/test/spec/VaultSpec.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev P2: the SAME VaultSpec, with only the vault hook pointing at the faulty copy.
contract P2_VaultNoPeriodTest is RealHooks, VaultSpec {
    function _newVault(IERC20 token, address faucet, uint16 dripBps, uint64 period)
        internal
        override(RealHooks, SpecBase)
        returns (IDripVault)
    {
        return IDripVault(address(new VaultNoPeriod(token, faucet, dripBps, period)));
    }
}
