// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {HookToken} from "contracts/test/mocks/HookToken.sol";
import {SplitAttacker} from "contracts/test/mocks/SplitAttacker.sol";

/// @dev Reentrancy through a hook token whose recipient (payee 0) is a malicious contract.
abstract contract SplitReentrancySpec is SplitSpecBase {
    bytes4 internal immutable REENTRANCY = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;

    HookToken internal token;
    IERC20 internal t;
    SplitAttacker internal attacker;
    ISplit internal split;

    function setUp() public virtual {
        _initTime();
        token = new HookToken();
        t = IERC20(address(token));
        attacker = new SplitAttacker();
        split = _newSplit(_pair(address(attacker), bob), _bps(7000, 3000));
        attacker.setUp(split, t);
        token.mint(address(split), 1000e18); // mint triggers no hook
    }

    function _assertCaught(uint8 mode) internal {
        attacker.attack(mode, false);

        assertEq(token.balanceOf(address(attacker)), 700e18, "attacker ends with exactly its share");
        assertEq(token.balanceOf(address(split)), 300e18, "bob's share is untouched");
        assertTrue(attacker.reentryAttempted(), "the hook did attempt a re-entry");
        assertFalse(attacker.reentryOk(), "the re-entry failed");
        assertEq(attacker.reentryRet(), abi.encodeWithSelector(REENTRANCY), "failed on the reentrancy guard");
        assertEq(split.pending(t, address(attacker)), 0);
        assertEq(split.pending(t, bob), 300e18);

        vm.prank(bob);
        assertEq(split.withdraw(t), 300e18, "bob can still withdraw his exact share");
    }

    function _assertBubbled(uint8 mode) internal {
        vm.expectRevert(REENTRANCY);
        attacker.attack(mode, true);

        assertEq(token.balanceOf(address(attacker)), 0, "attacker got nothing");
        assertEq(token.balanceOf(address(split)), 1000e18, "split untouched");
        assertEq(split.pending(t, address(attacker)), 0, "no state change at all (not even the release)");
        (uint256 accounted,,,,) = split.ledger(t);
        assertEq(accounted, 0);
    }

    function test_SplitReentrancy_WithdrawReentryIsCaughtAndPaysOnce() public {
        _assertCaught(0);
    }

    function test_SplitReentrancy_ReleaseReentryIsCaughtAndPaysOnce() public {
        _assertCaught(1);
    }

    function test_SplitReentrancy_BubbledWithdrawReentryRevertsEverything() public {
        _assertBubbled(0);
    }

    function test_SplitReentrancy_BubbledReleaseReentryRevertsEverything() public {
        _assertBubbled(1);
    }
}
