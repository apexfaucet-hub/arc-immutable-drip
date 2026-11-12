// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NoBackdoorSpec} from "contracts/test/spec/NoBackdoorSpec.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev NoBackdoorSpec against the production contracts.
contract NoBackdoorReal is RealHooks, NoBackdoorSpec {}
