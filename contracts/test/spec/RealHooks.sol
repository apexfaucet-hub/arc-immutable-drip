// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DripFaucet} from "contracts/DripFaucet.sol";
import {DripVault} from "contracts/DripVault.sol";
import {DripLaunchpad} from "contracts/DripLaunchpad.sol";
import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";

/// @dev Hooks that create the three PRODUCTION contracts.
abstract contract RealHooks is SpecBase {
    function _newFaucet(IERC20 token, uint256 claimAmount, uint64 cooldown)
        internal
        virtual
        override
        returns (IDripFaucet)
    {
        return IDripFaucet(address(new DripFaucet(token, claimAmount, cooldown)));
    }

    function _newVault(IERC20 token, address faucet, uint16 dripBps, uint64 period)
        internal
        virtual
        override
        returns (IDripVault)
    {
        return IDripVault(address(new DripVault(token, faucet, dripBps, period)));
    }

    function _newLaunchpad() internal virtual override returns (IDripLaunchpad) {
        return IDripLaunchpad(address(new DripLaunchpad()));
    }
}
