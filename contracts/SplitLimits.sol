// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared constants for the split contracts.
library SplitLimits {
    /// @dev Basis-point denominator. The two shares of a split must sum to exactly this.
    uint256 internal constant BPS_DENOMINATOR = 10_000;
}
