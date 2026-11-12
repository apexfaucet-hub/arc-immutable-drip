// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitCreditNotZeroed} from "planted/SplitCreditNotZeroed.sol";
import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";
import {SplitSpec} from "contracts/test/spec/SplitSpec.sol";
import {SplitBlocklistSpec} from "contracts/test/spec/SplitBlocklistSpec.sol";
import {SplitReentrancySpec} from "contracts/test/spec/SplitReentrancySpec.sol";
import {SplitInvariantSpec} from "contracts/test/spec/SplitInvariantSpec.sol";

/// @dev Split fault (c): the SAME split spec contracts, with only the split hook pointing at the faulty copy.
abstract contract SplitCreditNotZeroedHooks is RealSplitHooks {
    function _newSplit(address[2] memory payees, uint16[2] memory sharesBps)
        internal
        override
        returns (ISplit)
    {
        return ISplit(address(new SplitCreditNotZeroed(payees, sharesBps)));
    }
}

contract Sc_SplitCreditNotZeroed_SplitTest is SplitCreditNotZeroedHooks, SplitSpec {}

contract Sc_SplitCreditNotZeroed_BlocklistTest is SplitCreditNotZeroedHooks, SplitBlocklistSpec {}

contract Sc_SplitCreditNotZeroed_ReentrancyTest is SplitCreditNotZeroedHooks, SplitReentrancySpec {}

contract Sc_SplitCreditNotZeroed_InvariantTest is SplitCreditNotZeroedHooks, SplitInvariantSpec {}
