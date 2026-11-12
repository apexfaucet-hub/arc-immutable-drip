// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitInvariantSpec} from "contracts/test/spec/SplitInvariantSpec.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";

/// @dev SplitInvariantSpec against the production split contracts.
contract SplitInvariantReal is RealSplitHooks, SplitInvariantSpec {}
