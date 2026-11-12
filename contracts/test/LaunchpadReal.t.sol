// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LaunchpadSpec} from "contracts/test/spec/LaunchpadSpec.sol";
import {RealHooks} from "contracts/test/spec/RealHooks.sol";

/// @dev LaunchpadSpec against the production DripLaunchpad (with production vaults and faucets).
contract LaunchpadReal is RealHooks, LaunchpadSpec {}
