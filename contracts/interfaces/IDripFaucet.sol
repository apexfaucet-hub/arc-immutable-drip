// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Public surface of a drip faucet.
interface IDripFaucet {
    /// @notice Emitted when an address claims from the faucet.
    /// @param who The claimer (always the caller).
    /// @param amount The amount the faucet sent.
    event Claimed(address indexed who, uint256 amount);

    /// @notice The caller must wait until `nextClaimAt` before claiming again.
    error CooldownActive(uint256 nextClaimAt);
    /// @notice The faucet holds no tokens, so nothing can be claimed.
    error FaucetEmpty();
    /// @notice The token address was zero.
    error InvalidToken();
    /// @notice The claim amount was zero.
    error InvalidClaimAmount();
    /// @notice The cooldown was below the minimum.
    error CooldownTooShort(uint64 cooldown);

    /// @notice The token this faucet pays out.
    function token() external view returns (IERC20);

    /// @notice The maximum amount paid per claim.
    function claimAmount() external view returns (uint256);

    /// @notice Seconds an address must wait between two claims.
    function cooldown() external view returns (uint64);

    /// @notice Earliest timestamp at which `who` may claim again (0 = never claimed).
    function nextClaimAt(address who) external view returns (uint256);

    /// @notice Timestamp of the last claim by `who` (0 = never claimed).
    function lastClaim(address who) external view returns (uint256);

    /// @notice Claim up to `claimAmount` tokens for the caller.
    function claim() external returns (uint256 amount);
}
