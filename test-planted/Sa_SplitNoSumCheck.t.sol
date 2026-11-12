// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitNoSumCheck} from "planted/SplitNoSumCheck.sol";
import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";
import {SplitSpec} from "contracts/test/spec/SplitSpec.sol";
import {SplitBlocklistSpec} from "contracts/test/spec/SplitBlocklistSpec.sol";
import {SplitReentrancySpec} from "contracts/test/spec/SplitReentrancySpec.sol";
import {SplitInvariantSpec} from "contracts/test/spec/SplitInvariantSpec.sol";

/// @dev Split fault (a): the SAME split spec contracts, with only the split hook pointing at the faulty copy.
abstract contract SplitNoSumCheckHooks is RealSplitHooks {
    function _newSplit(address[2] memory payees, uint16[2] memory sharesBps)
        internal
        override
        returns (ISplit)
    {
        return ISplit(address(new SplitNoSumCheck(payees, sharesBps)));
    }
}

contract Sa_SplitNoSumCheck_SplitTest is SplitNoSumCheckHooks, SplitSpec {}

contract Sa_SplitNoSumCheck_BlocklistTest is SplitNoSumCheckHooks, SplitBlocklistSpec {}

contract Sa_SplitNoSumCheck_ReentrancyTest is SplitNoSumCheckHooks, SplitReentrancySpec {}

contract Sa_SplitNoSumCheck_InvariantTest is SplitNoSumCheckHooks, SplitInvariantSpec {}

import {SplitFactoryNoSumCheck} from "planted/SplitFactoryNoSumCheck.sol";
import {ISplitFactory} from "contracts/interfaces/ISplitFactory.sol";
import {SplitFactorySpec} from "contracts/test/spec/SplitFactorySpec.sol";

/// @dev Same fault seen through the factory: it deploys the faulty split, so the factory spec must fail too.
abstract contract SplitFactoryNoSumCheckHooks is RealSplitHooks {
    function _newSplitFactory() internal override returns (ISplitFactory) {
        return ISplitFactory(address(new SplitFactoryNoSumCheck()));
    }
}

contract Sa_SplitNoSumCheck_FactoryTest is SplitFactoryNoSumCheckHooks, SplitFactorySpec {}
