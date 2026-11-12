// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InvariantSpec} from "contracts/test/spec/InvariantSpec.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev InvariantSpec against the production contracts.
contract InvariantReal is RealHooks, InvariantSpec {}
