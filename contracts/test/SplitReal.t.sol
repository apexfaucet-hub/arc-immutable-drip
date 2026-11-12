// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitSpec} from "contracts/test/spec/SplitSpec.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";

/// @dev SplitSpec against the production split contracts.
contract SplitReal is RealSplitHooks, SplitSpec {}
