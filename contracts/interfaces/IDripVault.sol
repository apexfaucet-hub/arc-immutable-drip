// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Public surface of a drip vault.
interface IDripVault {
    /// @notice Emitted when the vault drips tokens into its faucet.
    /// @param amount The amount the vault sent.
    /// @param remaining The vault balance measured after the transfer.
    event Dripped(uint256 amount, uint256 remaining);

    /// @notice The next drip is not available until `nextDripAt`.
    error DripTooSoon(uint256 nextDripAt);
    /// @notice The computed drip is zero (dust), so nothing is sent.
    error NothingToDrip();
    /// @notice The token address was zero.
    error InvalidToken();
    /// @notice The faucet address was zero.
    error InvalidFaucet();
    /// @notice dripBps was outside 1..9999.
    error InvalidDripBps(uint16 dripBps);
    /// @notice The period was below the minimum.
    error PeriodTooShort(uint64 period);

    /// @notice The token held by this vault.
    function token() external view returns (IERC20);

    /// @notice The faucet that receives every drip.
    function faucet() external view returns (address);

    /// @notice Share of the vault balance dripped each time, in basis points.
    function dripBps() external view returns (uint16);

    /// @notice Seconds between two drips.
    function period() external view returns (uint64);

    /// @notice Earliest timestamp at which the next drip is available.
    function nextDripAt() external view returns (uint256);

    /// @notice Move `dripBps` of the vault balance to the faucet.
    function drip() external returns (uint256 amount);
}
