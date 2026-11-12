// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LaunchpadTrustsAmount} from "planted/LaunchpadTrustsAmount.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {LaunchpadSpec} from "contracts/test/spec/LaunchpadSpec.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev P4: the SAME LaunchpadSpec, with only the launchpad hook pointing at the faulty copy.
contract P4_LaunchpadTrustsAmountTest is RealHooks, LaunchpadSpec {
    function _newLaunchpad() internal override(RealHooks, SpecBase) returns (IDripLaunchpad) {
        return IDripLaunchpad(address(new LaunchpadTrustsAmount()));
    }
}
