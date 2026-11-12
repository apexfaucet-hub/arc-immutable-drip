// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultSpec} from "contracts/test/spec/VaultSpec.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev VaultSpec against the production DripVault.
contract VaultReal is RealHooks, VaultSpec {}
