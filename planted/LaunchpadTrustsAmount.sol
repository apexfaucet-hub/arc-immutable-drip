// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {DripLimits} from "contracts/DripLimits.sol";
import {DripFaucet} from "contracts/DripFaucet.sol";
import {DripVault} from "contracts/DripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";

/// @notice Permissionless factory for drip vaults and faucets. No owner, no fee, no constructor
/// arguments, and it never holds tokens: tokens go straight from the launcher to the new vault.
contract LaunchpadTrustsAmount is IDripLaunchpad, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Launch {
        address vault;
        address faucet;
    }

    Launch[] private _launches;

    /// @inheritdoc IDripLaunchpad
    function launchCount() external view returns (uint256) {
        return _launches.length;
    }

    /// @inheritdoc IDripLaunchpad
    function launches(uint256 id) external view returns (address vault, address faucet) {
        if (id >= _launches.length) revert UnknownLaunch(id);
        Launch storage l = _launches[id];
        return (l.vault, l.faucet);
    }

    /// @inheritdoc IDripLaunchpad
    /// @dev Always pulls from `msg.sender`, never from another address. The vault is credited with the
    /// measured balance difference, so a fee-on-transfer token cannot fake a balance.
    function launch(
        IERC20 token,
        uint256 amount,
        uint16 dripBps,
        uint64 period,
        uint256 claimAmount,
        uint64 cooldown
    ) external nonReentrant returns (uint256 id, address vault, address faucet) {
        if (address(token) == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (dripBps == 0 || dripBps > DripLimits.MAX_DRIP_BPS) revert InvalidDripBps(dripBps);
        if (period < DripLimits.MIN_PERIOD) revert PeriodTooShort(period);
        if (claimAmount == 0) revert InvalidClaimAmount();
        if (cooldown < DripLimits.MIN_COOLDOWN) revert CooldownTooShort(cooldown);

        faucet = address(new DripFaucet(token, claimAmount, cooldown));
        vault = address(new DripVault(token, faucet, dripBps, period));
        id = _launches.length;
        _launches.push(Launch(vault, faucet));

        uint256 balanceBefore = token.balanceOf(vault);
        token.safeTransferFrom(msg.sender, vault, amount);
        uint256 received = amount;
        if (received == 0) revert NothingReceived();

        emit Launched(id, address(token), vault, faucet, msg.sender, received, dripBps, period, claimAmount, cooldown);
    }
}
