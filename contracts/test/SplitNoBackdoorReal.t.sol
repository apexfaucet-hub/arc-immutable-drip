// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitNoBackdoorSpec} from "contracts/test/spec/SplitNoBackdoorSpec.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";

/// @dev SplitNoBackdoorSpec against the production split contracts.
contract SplitNoBackdoorReal is RealSplitHooks, SplitNoBackdoorSpec {}
