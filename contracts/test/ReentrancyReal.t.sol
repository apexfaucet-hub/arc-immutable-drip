// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancySpec} from "contracts/test/spec/ReentrancySpec.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev ReentrancySpec against the production contracts.
contract ReentrancyReal is RealHooks, ReentrancySpec {}
