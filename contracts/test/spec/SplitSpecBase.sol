// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {ISplitFactory} from "contracts/interfaces/ISplitFactory.sol";

/// @dev Shared base of the split spec contracts. Concrete contracts choose which implementation sits
/// behind the two hooks: the production contracts (`RealSplitHooks`) or a faulty planted copy.
abstract contract SplitSpecBase is Test {
    uint256 internal constant T0 = 1_750_000_000;

    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal random = makeAddr("random");

    function _initTime() internal {
        vm.warp(T0);
    }

    function _newSplit(address[2] memory payees, uint16[2] memory sharesBps) internal virtual returns (ISplit);

    function _newSplitFactory() internal virtual returns (ISplitFactory);

    function _pair(address a, address b) internal pure returns (address[2] memory p) {
        p = [a, b];
    }

    function _bps(uint16 a, uint16 b) internal pure returns (uint16[2] memory s) {
        s = [a, b];
    }
}
