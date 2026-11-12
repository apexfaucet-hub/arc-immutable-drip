// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SplitFactorySpec} from "contracts/test/spec/SplitFactorySpec.sol";
import {RealSplitHooks} from "contracts/test/spec/RealSplitHooks.sol";

/// @dev SplitFactorySpec against the production split contracts.
contract SplitFactoryReal is RealSplitHooks, SplitFactorySpec {}
