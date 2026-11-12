// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Split} from "contracts/Split.sol";
import {SplitFactory} from "contracts/SplitFactory.sol";
import {ISplit} from "contracts/interfaces/ISplit.sol";
import {ISplitFactory} from "contracts/interfaces/ISplitFactory.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";

/// @dev Hooks that create the PRODUCTION split contracts.
abstract contract RealSplitHooks is SplitSpecBase {
    function _newSplit(address[2] memory payees, uint16[2] memory sharesBps)
        internal
        virtual
        override
        returns (ISplit)
    {
        return ISplit(address(new Split(payees, sharesBps)));
    }

    function _newSplitFactory() internal virtual override returns (ISplitFactory) {
        return ISplitFactory(address(new SplitFactory()));
    }
}
