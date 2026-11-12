// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {HookToken} from "contracts/test/mocks/HookToken.sol";
import {ReentrantToken} from "contracts/test/mocks/ReentrantToken.sol";
import {ClaimAttacker} from "contracts/test/mocks/ClaimAttacker.sol";

/// @dev Reentrancy through malicious tokens (case 9).
abstract contract ReentrancySpec is SpecBase {
    uint256 internal constant CLAIM = 10e18;
    uint64 internal constant COOLDOWN = 8 hours;

    bytes4 internal immutable REENTRANCY = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;

    HookToken internal hook;
    IDripFaucet internal faucet;
    ClaimAttacker internal attacker;

    function setUp() public virtual {
        _initTime();
        hook = new HookToken();
        faucet = _newFaucet(IERC20(address(hook)), CLAIM, COOLDOWN);
        hook.mint(address(faucet), 5 * CLAIM); // at least 3x claimAmount
        attacker = new ClaimAttacker(faucet);
    }

    /// The attacker catches the failed re-entry: the outer claim completes exactly once.
    function test_Reentrancy_ClaimReentryFailsAndOuterClaimPaysOnce() public {
        attacker.attack(false);

        assertEq(hook.balanceOf(address(attacker)), CLAIM, "attacker ends with exactly ONE claimAmount");
        assertEq(hook.balanceOf(address(faucet)), 4 * CLAIM, "faucet paid exactly once");
        assertTrue(attacker.reentryAttempted(), "the hook did attempt a re-entry");
        assertFalse(attacker.reentryOk(), "the re-entry failed");
        assertEq(attacker.reentryRet(), abi.encodeWithSelector(REENTRANCY), "failed on the reentrancy guard");
        assertEq(faucet.nextClaimAt(address(attacker)), T0 + COOLDOWN);
    }

    /// The attacker lets the failed re-entry bubble: the whole claim reverts with no state change.
    function test_Reentrancy_BubbledClaimReentryRevertsEverything() public {
        vm.expectRevert(REENTRANCY);
        attacker.attack(true);

        assertEq(hook.balanceOf(address(attacker)), 0, "attacker got nothing");
        assertEq(hook.balanceOf(address(faucet)), 5 * CLAIM, "faucet untouched");
        assertEq(faucet.nextClaimAt(address(attacker)), 0, "cooldown not consumed");
        assertFalse(attacker.reentryAttempted() && attacker.reentryOk());
    }

    /// A token whose transfer re-enters drip(): the re-entry fails, one drip only.
    function test_Reentrancy_DripReentryFails() public {
        address faucetAddr = makeAddr("faucetSink");
        ReentrantToken rt = new ReentrantToken();
        IDripVault vault = _newVault(IERC20(address(rt)), faucetAddr, 100, 1 days);
        rt.mint(address(vault), 1_000e18);
        rt.arm(address(vault), abi.encodeCall(IDripVault.drip, ()), false);

        vm.prank(alice);
        assertEq(vault.drip(), 10e18, "exactly one drip");

        assertEq(rt.calls(), 1, "the token attempted the re-entry");
        assertFalse(rt.lastOk(), "the re-entry failed");
        assertEq(rt.lastRet(), abi.encodeWithSelector(REENTRANCY), "failed on the reentrancy guard");
        assertEq(rt.balanceOf(faucetAddr), 10e18);
        assertEq(rt.balanceOf(address(vault)), 990e18);
        assertEq(vault.nextDripAt(), T0 + 1 days);
    }

    /// A token whose transferFrom re-enters launch(): the re-entry fails, one launch only.
    function test_Reentrancy_LaunchReentryFails() public {
        IDripLaunchpad lp = _newLaunchpad();
        ReentrantToken rt = new ReentrantToken();
        rt.mint(launcher, 1_000e18);
        vm.prank(launcher);
        rt.approve(address(lp), type(uint256).max);
        rt.arm(
            address(lp),
            abi.encodeCall(IDripLaunchpad.launch, (IERC20(address(rt)), 1e18, 100, 1 days, CLAIM, COOLDOWN)),
            true
        );

        vm.prank(launcher);
        (uint256 id, address vault,) = lp.launch(IERC20(address(rt)), 500e18, 100, 1 days, CLAIM, COOLDOWN);

        assertEq(id, 0);
        assertEq(rt.calls(), 1, "the token attempted the re-entry");
        assertFalse(rt.lastOk(), "the re-entry failed");
        assertEq(rt.lastRet(), abi.encodeWithSelector(REENTRANCY), "failed on the reentrancy guard");
        assertEq(lp.launchCount(), 1, "exactly one launch");
        assertEq(rt.balanceOf(vault), 500e18);
        assertEq(rt.balanceOf(address(lp)), 0);
        assertEq(rt.balanceOf(launcher), 500e18);
    }
}
