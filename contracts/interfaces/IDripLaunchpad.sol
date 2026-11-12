// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Public surface of the drip launchpad factory.
interface IDripLaunchpad {
    /// @notice Emitted once per launch.
    /// @param id Index of the launch.
    /// @param token The launched token.
    /// @param vault The new vault.
    /// @param faucet The new faucet.
    /// @param launcher The caller that funded the vault.
    /// @param amountReceived Tokens that actually arrived in the vault (balance difference).
    /// @param dripBps Vault drip share in basis points.
    /// @param period Seconds between two drips.
    /// @param claimAmount Maximum amount per faucet claim.
    /// @param cooldown Seconds between two claims by one address.
    event Launched(
        uint256 indexed id,
        address indexed token,
        address vault,
        address faucet,
        address indexed launcher,
        uint256 amountReceived,
        uint16 dripBps,
        uint64 period,
        uint256 claimAmount,
        uint64 cooldown
    );

    /// @notice The token address was zero.
    error InvalidToken();
    /// @notice The amount was zero.
    error InvalidAmount();
    /// @notice dripBps was outside 1..9999.
    error InvalidDripBps(uint16 dripBps);
    /// @notice The period was below the minimum.
    error PeriodTooShort(uint64 period);
    /// @notice The claim amount was zero.
    error InvalidClaimAmount();
    /// @notice The cooldown was below the minimum.
    error CooldownTooShort(uint64 cooldown);
    /// @notice No tokens arrived in the vault.
    error NothingReceived();
    /// @notice There is no launch with this id.
    error UnknownLaunch(uint256 id);

    /// @notice Number of launches so far.
    function launchCount() external view returns (uint256);

    /// @notice The vault and faucet of launch `id`.
    function launches(uint256 id) external view returns (address vault, address faucet);

    /// @notice Launch a new vault and faucet, funded by the caller.
    function launch(
        IERC20 token,
        uint256 amount,
        uint16 dripBps,
        uint64 period,
        uint256 claimAmount,
        uint64 cooldown
    ) external returns (uint256 id, address vault, address faucet);
}
