// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {DripLimits} from "contracts/DripLimits.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";

/// @notice Immutable vault: anyone may move `dripBps` of the vault balance to the faucet once per `period`.
/// No owner, no admin, no way to move tokens except through `drip()`.
contract DripVault is IDripVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @inheritdoc IDripVault
    IERC20 public immutable token;
    /// @inheritdoc IDripVault
    address public immutable faucet;
    /// @inheritdoc IDripVault
    uint16 public immutable dripBps;
    /// @inheritdoc IDripVault
    uint64 public immutable period;

    /// @inheritdoc IDripVault
    uint256 public nextDripAt;

    /// @dev The first drip is available immediately: `nextDripAt` starts at the deployment timestamp.
    /// @param token_ The token held by the vault (non-zero).
    /// @param faucet_ The faucet that receives every drip (non-zero).
    /// @param dripBps_ Share of the balance dripped each time, 1..9999.
    /// @param period_ Seconds between two drips (>= DripLimits.MIN_PERIOD).
    constructor(IERC20 token_, address faucet_, uint16 dripBps_, uint64 period_) {
        if (address(token_) == address(0)) revert InvalidToken();
        if (faucet_ == address(0)) revert InvalidFaucet();
        if (dripBps_ == 0 || dripBps_ > DripLimits.MAX_DRIP_BPS) revert InvalidDripBps(dripBps_);
        if (period_ < DripLimits.MIN_PERIOD) revert PeriodTooShort(period_);
        token = token_;
        faucet = faucet_;
        dripBps = dripBps_;
        period = period_;
        nextDripAt = block.timestamp;
    }

    /// @inheritdoc IDripVault
    /// @dev Callable by anyone. Missed periods do NOT accumulate: one drip per call, then the clock
    /// restarts at `block.timestamp`. Reverts with `NothingToDrip` on dust (no state change).
    function drip() external nonReentrant returns (uint256 amount) {
        if (block.timestamp < nextDripAt) revert DripTooSoon(nextDripAt);
        uint256 bal = token.balanceOf(address(this));
        amount = Math.mulDiv(bal, dripBps, DripLimits.BPS_DENOMINATOR);
        if (amount == 0) revert NothingToDrip();
        nextDripAt = block.timestamp + period;
        token.safeTransfer(faucet, amount);
        emit Dripped(amount, token.balanceOf(address(this)));
    }
}
