// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {BlocklistToken} from "contracts/test/mocks/BlocklistToken.sol";

/// @dev A token that rejects one payee must not lock the other payee's funds.
abstract contract SplitBlocklistSpec is SplitSpecBase {
    BlocklistToken internal token;
    IERC20 internal t;
    ISplit internal split;

    function setUp() public virtual {
        _initTime();
        token = new BlocklistToken();
        t = IERC20(address(token));
        split = _newSplit(_pair(alice, bob), _bps(7000, 3000));
    }

    function test_Blocklist_BlockedPayeeDoesNotLockTheOtherPayee() public {
        token.mint(address(split), 1000e18);
        token.setBlocked(alice, true);

        // release is unaffected: it moves no tokens.
        (uint256 a0, uint256 a1) = split.release(t);
        assertEq(a0, 700e18);
        assertEq(a1, 300e18);

        // the blocked payee cannot be paid ...
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, alice));
        split.withdraw(t);
        assertEq(split.pending(t, alice), 700e18, "alice's credit is preserved");

        // ... but the other payee gets exactly his share, right now.
        vm.prank(bob);
        assertEq(split.withdraw(t), 300e18);
        assertEq(token.balanceOf(bob), 300e18);
        assertEq(token.balanceOf(address(split)), 700e18, "only alice's credit remains");
    }

    function test_Blocklist_OtherPayeeKeepsWorkingOverNewDeposits() public {
        token.setBlocked(alice, true);
        token.mint(address(split), 1000e18);
        vm.prank(bob);
        assertEq(split.withdraw(t), 300e18);

        token.mint(address(split), 100e18);
        split.release(t);
        vm.prank(bob);
        assertEq(split.withdraw(t), 30e18);
        assertEq(split.pending(t, alice), 770e18, "alice accrues 70% of both deposits");
        assertEq(token.balanceOf(address(split)), 770e18);
    }

    function test_Blocklist_UnblockedPayeeCanWithdrawEverythingLater() public {
        token.mint(address(split), 1000e18);
        token.setBlocked(alice, true);
        vm.prank(bob);
        split.withdraw(t);

        token.setBlocked(alice, false);
        vm.prank(alice);
        assertEq(split.withdraw(t), 700e18);
        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(address(split)), 0);
    }

    function test_Blocklist_BlockedSecondPayeeDoesNotLockTheFirst() public {
        token.mint(address(split), 1000e18);
        token.setBlocked(bob, true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, bob));
        split.withdraw(t);
        vm.prank(alice);
        assertEq(split.withdraw(t), 700e18);
    }

    function test_Blocklist_AnyoneCanStillRelease() public {
        token.mint(address(split), 1000e18);
        token.setBlocked(alice, true);
        token.setBlocked(bob, true);
        vm.prank(random);
        (uint256 a0, uint256 a1) = split.release(t);
        assertEq(a0, 700e18);
        assertEq(a1, 300e18);
    }
}
