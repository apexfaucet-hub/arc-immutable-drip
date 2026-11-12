// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitPaysAllToPayee0} from "planted/SplitPaysAllToPayee0.sol";
import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";
import {SplitSpec} from "contracts/test/spec/SplitSpec.sol";
import {SplitBlocklistSpec} from "contracts/test/spec/SplitBlocklistSpec.sol";
import {SplitReentrancySpec} from "contracts/test/spec/SplitReentrancySpec.sol";
import {SplitInvariantSpec} from "contracts/test/spec/SplitInvariantSpec.sol";

/// @dev Split fault (b): the SAME split spec contracts, with only the split hook pointing at the faulty copy.
abstract contract SplitPaysAllToPayee0Hooks is RealSplitHooks {
    function _newSplit(address[2] memory payees, uint16[2] memory sharesBps)
        internal
        override
        returns (ISplit)
    {
        return ISplit(address(new SplitPaysAllToPayee0(payees, sharesBps)));
    }
}

contract Sb_SplitPaysAllToPayee0_SplitTest is SplitPaysAllToPayee0Hooks, SplitSpec {}

contract Sb_SplitPaysAllToPayee0_BlocklistTest is SplitPaysAllToPayee0Hooks, SplitBlocklistSpec {}

contract Sb_SplitPaysAllToPayee0_ReentrancyTest is SplitPaysAllToPayee0Hooks, SplitReentrancySpec {}

contract Sb_SplitPaysAllToPayee0_InvariantTest is SplitPaysAllToPayee0Hooks, SplitInvariantSpec {}
