// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitBlocklistSpec} from "contracts/test/spec/SplitBlocklistSpec.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";

/// @dev SplitBlocklistSpec against the production split contracts.
contract SplitBlocklistReal is RealSplitHooks, SplitBlocklistSpec {}
