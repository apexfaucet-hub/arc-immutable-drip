// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared bounds for the drip launchpad. Used by the factory AND by the vault and
/// faucet constructors, so a vault or faucet deployed standalone is exactly as safe.
library DripLimits {
    /// @dev Basis-point denominator.
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev Largest allowed dripBps. 10_000 is rejected on purpose: it would empty the vault in
    /// one drip, which breaks "the vault never runs out".
    uint16 internal constant MAX_DRIP_BPS = 9_999;

    /// @dev Smallest allowed time between two drips. There is no upper bound.
    uint64 internal constant MIN_PERIOD = 1 hours;

    /// @dev Smallest allowed time between two claims by one address. There is no upper bound
    /// (type(uint64).max means "claim once ever").
    uint64 internal constant MIN_COOLDOWN = 1 minutes;
}
