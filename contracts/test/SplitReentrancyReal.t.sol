// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitReentrancySpec} from "contracts/test/spec/SplitReentrancySpec.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";

/// @dev SplitReentrancySpec against the production split contracts.
contract SplitReentrancyReal is RealSplitHooks, SplitReentrancySpec {}
