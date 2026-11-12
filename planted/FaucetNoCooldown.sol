// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {DripLimits} from "contracts/DripLimits.sol";
import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";

/// @notice Immutable faucet: every address may claim up to `claimAmount` tokens, once per `cooldown`.
/// No owner, no admin, no way to move tokens except through `claim()`.
contract FaucetNoCooldown is IDripFaucet, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @inheritdoc IDripFaucet
    IERC20 public immutable token;
    /// @inheritdoc IDripFaucet
    uint256 public immutable claimAmount;
    /// @inheritdoc IDripFaucet
    uint64 public immutable cooldown;

    /// @inheritdoc IDripFaucet
    /// @dev 0 means never claimed, claimable now.
    mapping(address => uint256) public nextClaimAt;

    /// @param token_ The token to pay out (non-zero).
    /// @param claimAmount_ Maximum amount per claim (non-zero).
    /// @param cooldown_ Seconds between two claims by one address (>= DripLimits.MIN_COOLDOWN).
    constructor(IERC20 token_, uint256 claimAmount_, uint64 cooldown_) {
        if (address(token_) == address(0)) revert InvalidToken();
        if (claimAmount_ == 0) revert InvalidClaimAmount();
        if (cooldown_ < DripLimits.MIN_COOLDOWN) revert CooldownTooShort(cooldown_);
        token = token_;
        claimAmount = claimAmount_;
        cooldown = cooldown_;
    }

    /// @inheritdoc IDripFaucet
    function lastClaim(address who) external view returns (uint256) {
        uint256 next = nextClaimAt[who];
        return next == 0 ? 0 : next - cooldown;
    }

    /// @inheritdoc IDripFaucet
    /// @dev Always pays `msg.sender`. If the faucet holds less than `claimAmount` it pays what it has.
    /// If it holds nothing it reverts with `FaucetEmpty`: no state change, the caller's cooldown is NOT
    /// consumed, no zero-value transfer and no event.
    function claim() external nonReentrant returns (uint256 amount) {
        uint256 bal = token.balanceOf(address(this));
        amount = bal < claimAmount ? bal : claimAmount;
        if (amount == 0) revert FaucetEmpty();
        nextClaimAt[msg.sender] = block.timestamp + cooldown;
        token.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }
}
