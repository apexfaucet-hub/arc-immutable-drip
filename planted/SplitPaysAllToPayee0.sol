// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SplitLimits} from "contracts/SplitLimits.sol";
import {ISplit} from "contracts/interfaces/ISplit.sol";

/// @notice Immutable two-payee revenue split for ERC-20 tokens. No owner, no admin, no upgrade, no pause.
/// Payees and shares are fixed in the constructor. `release` credits each payee its share of everything
/// received so far; each payee pulls its own credit with `withdraw`, so a payee that cannot receive a
/// token (for example a blocklisted address) can never block the other payee.
/// There is no `receive`, no `fallback` and no payable function: native value cannot be sent to a split.
contract SplitPaysAllToPayee0 is ISplit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Per-token accounting.
    /// accounted: cumulative inflow recognised so far (monotonic).
    /// accrued0/1: cumulative credit to each payee, always floor(accounted * share / 10000) (monotonic).
    /// pending0/1: credit a payee can withdraw now (zeroed on withdraw).
    /// Tokens held == pending0 + pending1 + (accounted - accrued0 - accrued1) as long as the token is
    /// well behaved; the last term is rounding dust (at most 1 unit) that stays for the next release.
    struct Ledger {
        uint256 accounted;
        uint256 accrued0;
        uint256 accrued1;
        uint256 pending0;
        uint256 pending1;
    }

    /// @inheritdoc ISplit
    address public immutable payee0;
    /// @inheritdoc ISplit
    address public immutable payee1;
    /// @inheritdoc ISplit
    uint16 public immutable shares0;
    /// @inheritdoc ISplit
    uint16 public immutable shares1;

    /// @inheritdoc ISplit
    mapping(IERC20 => Ledger) public ledger;

    /// @param payees The two payees (non-zero, distinct).
    /// @param sharesBps Their shares in basis points (each > 0, sum exactly 10000).
    constructor(address[2] memory payees, uint16[2] memory sharesBps) {
        if (payees[0] == address(0) || payees[1] == address(0)) revert ZeroPayee();
        if (payees[0] == payees[1]) revert DuplicatePayees();
        if (sharesBps[0] == 0 || sharesBps[1] == 0) revert ZeroShare();
        if (uint256(sharesBps[0]) + sharesBps[1] != SplitLimits.BPS_DENOMINATOR) {
            revert SharesDoNotSumToBasisPoints(uint256(sharesBps[0]) + sharesBps[1]);
        }
        payee0 = payees[0];
        payee1 = payees[1];
        shares0 = sharesBps[0];
        shares1 = sharesBps[1];
    }

    /// @inheritdoc ISplit
    function pending(IERC20 token, address who) external view returns (uint256) {
        Ledger storage l = ledger[token];
        if (who == payee0) return l.pending0;
        if (who == payee1) return l.pending1;
        return 0;
    }

    /// @inheritdoc ISplit
    /// @dev Callable by anyone, for any ERC-20. Never reverts because of rounding dust: a release that
    /// finds nothing new simply credits 0 and 0. Dust (at most 1 unit) stays in the split and is folded
    /// into the next release because credit is always computed on the cumulative inflow.
    function release(IERC20 token) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = _sync(token);
        emit Released(token, amount0, amount1);
    }

    /// @inheritdoc ISplit
    /// @dev Only a payee can call it. It first accounts for any unreleased tokens, then zeroes the
    /// caller's credit BEFORE sending it. If the token refuses to pay this payee, only this call
    /// reverts: the other payee's credit is untouched and withdrawable.
    function withdraw(IERC20 token) external nonReentrant returns (uint256 amount) {
        if (msg.sender != payee0 && msg.sender != payee1) revert NotPayee(msg.sender);
        (uint256 amount0, uint256 amount1) = _sync(token);
        if (amount0 != 0 || amount1 != 0) emit Released(token, amount0, amount1);

        Ledger storage l = ledger[token];
        if (msg.sender == payee0) {
            amount = l.pending0;
            l.pending0 = 0;
        } else {
            amount = l.pending1;
            l.pending1 = 0;
        }
        if (amount == 0) revert NothingToWithdraw();
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(token, msg.sender, amount);
    }

    /// @dev Recognise newly received tokens and credit both payees. Pure accounting plus one `balanceOf`
    /// (a STATICCALL, so a hostile token cannot re-enter through it).
    function _sync(IERC20 token) private returns (uint256 amount0, uint256 amount1) {
        if (address(token) == address(0)) revert InvalidToken();
        Ledger storage l = ledger[token];

        uint256 expected = l.pending0 + l.pending1 + (l.accounted - l.accrued0 - l.accrued1);
        uint256 bal = token.balanceOf(address(this));
        if (bal > expected) l.accounted += bal - expected;

        uint256 e0 = l.accounted;
        uint256 e1 = 0;
        amount0 = e0 - l.accrued0;
        amount1 = e1 - l.accrued1;
        l.accrued0 = e0;
        l.accrued1 = e1;
        l.pending0 += amount0;
        l.pending1 += amount1;
    }
}
