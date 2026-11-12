// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FaucetSpec} from "contracts/test/spec/FaucetSpec.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev FaucetSpec against the production DripFaucet.
contract FaucetReal is RealHooks, FaucetSpec {}
