// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Public surface of an immutable two-payee revenue split (ERC-20 only).
interface ISplit {
    /// @notice Emitted by `release`: the amounts newly credited to each payee.
    /// @param token The token that was released.
    /// @param amount0 Newly credited to payee 0 (withdrawable by payee 0).
    /// @param amount1 Newly credited to payee 1 (withdrawable by payee 1).
    event Released(IERC20 indexed token, uint256 amount0, uint256 amount1);

    /// @notice Emitted when a payee withdraws its credit.
    /// @param token The token paid out.
    /// @param payee The payee (always the caller).
    /// @param amount The amount sent.
    event Withdrawn(IERC20 indexed token, address indexed payee, uint256 amount);

    /// @notice A payee address was zero.
    error ZeroPayee();
    /// @notice Both payees were the same address.
    error DuplicatePayees();
    /// @notice A share was zero.
    error ZeroShare();
    /// @notice The two shares did not sum to exactly 10000.
    error SharesDoNotSumToBasisPoints(uint256 sum);
    /// @notice The token address was zero.
    error InvalidToken();
    /// @notice The caller is not one of the two payees.
    error NotPayee(address caller);
    /// @notice The caller has nothing to withdraw.
    error NothingToWithdraw();

    /// @notice First payee.
    function payee0() external view returns (address);

    /// @notice Second payee.
    function payee1() external view returns (address);

    /// @notice Share of payee 0 in basis points.
    function shares0() external view returns (uint16);

    /// @notice Share of payee 1 in basis points.
    function shares1() external view returns (uint16);

    /// @notice Accounting for `token`: cumulative accounted inflow, cumulative credit per payee, and
    /// the credit each payee can withdraw right now.
    function ledger(IERC20 token)
        external
        view
        returns (uint256 accounted, uint256 accrued0, uint256 accrued1, uint256 pending0, uint256 pending1);

    /// @notice Credit that `who` can withdraw now (0 for any address that is not a payee).
    function pending(IERC20 token, address who) external view returns (uint256);

    /// @notice Account for every new token received and credit each payee its share. Anyone may call.
    function release(IERC20 token) external returns (uint256 amount0, uint256 amount1);

    /// @notice Pay the caller (a payee) its credit in `token`.
    function withdraw(IERC20 token) external returns (uint256 amount);
}
