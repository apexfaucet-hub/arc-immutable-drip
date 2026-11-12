// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";
import {FeeToken} from "contracts/test/mocks/FeeToken.sol";

/// @dev Behaviour of a Split with a 70/30 configuration. Runs against whatever `_newSplit` returns.
abstract contract SplitSpec is SplitSpecBase {
    MockERC20 internal token;
    IERC20 internal t;
    ISplit internal split;

    function setUp() public virtual {
        _initTime();
        token = new MockERC20();
        t = IERC20(address(token));
        split = _newSplit(_pair(alice, bob), _bps(7000, 3000));
    }

    function _acc() internal view returns (uint256 accounted, uint256 a0, uint256 a1, uint256 p0, uint256 p1) {
        return split.ledger(t);
    }

    // ------------------------------------------------------------ construction
    function test_Split_Immutables() public view {
        assertEq(split.payee0(), alice);
        assertEq(split.payee1(), bob);
        assertEq(split.shares0(), 7000);
        assertEq(split.shares1(), 3000);
    }

    function test_Split_RejectsZeroPayee() public {
        vm.expectRevert(ISplit.ZeroPayee.selector);
        _newSplit(_pair(address(0), bob), _bps(7000, 3000));
        vm.expectRevert(ISplit.ZeroPayee.selector);
        _newSplit(_pair(alice, address(0)), _bps(7000, 3000));
    }

    function test_Split_RejectsDuplicatePayees() public {
        vm.expectRevert(ISplit.DuplicatePayees.selector);
        _newSplit(_pair(alice, alice), _bps(7000, 3000));
    }

    function test_Split_RejectsZeroShare() public {
        vm.expectRevert(ISplit.ZeroShare.selector);
        _newSplit(_pair(alice, bob), _bps(0, 10_000));
        vm.expectRevert(ISplit.ZeroShare.selector);
        _newSplit(_pair(alice, bob), _bps(10_000, 0));
    }

    function test_Split_RejectsSharesNotSummingTo10000() public {
        vm.expectRevert(abi.encodeWithSelector(ISplit.SharesDoNotSumToBasisPoints.selector, uint256(9_999)));
        _newSplit(_pair(alice, bob), _bps(5000, 4999));
        vm.expectRevert(abi.encodeWithSelector(ISplit.SharesDoNotSumToBasisPoints.selector, uint256(10_001)));
        _newSplit(_pair(alice, bob), _bps(5000, 5001));
        vm.expectRevert(abi.encodeWithSelector(ISplit.SharesDoNotSumToBasisPoints.selector, uint256(12_000)));
        _newSplit(_pair(alice, bob), _bps(7000, 5000));
        // No uint16 overflow tricks: 65535 + 65535 is summed as uint256.
        vm.expectRevert(abi.encodeWithSelector(ISplit.SharesDoNotSumToBasisPoints.selector, uint256(131_070)));
        _newSplit(_pair(alice, bob), _bps(type(uint16).max, type(uint16).max));
    }

    function test_Split_AcceptsBoundaryShares() public {
        ISplit a = _newSplit(_pair(alice, bob), _bps(1, 9999));
        assertEq(a.shares0(), 1);
        assertEq(a.shares1(), 9999);
        ISplit b = _newSplit(_pair(alice, bob), _bps(9999, 1));
        assertEq(b.shares0(), 9999);
        ISplit c = _newSplit(_pair(alice, bob), _bps(5000, 5000));
        assertEq(c.shares1(), 5000);
    }

    // ------------------------------------------------------------ release / withdraw
    function test_Split_ReleaseCreditsExactSharesAndEmits() public {
        token.mint(address(split), 1000e18);

        vm.expectEmit(true, false, false, true, address(split));
        emit ISplit.Released(t, 700e18, 300e18);
        vm.prank(random);
        (uint256 a0, uint256 a1) = split.release(t);

        assertEq(a0, 700e18);
        assertEq(a1, 300e18);
        assertEq(split.pending(t, alice), 700e18);
        assertEq(split.pending(t, bob), 300e18);
        assertEq(split.pending(t, random), 0);
        (uint256 accounted, uint256 acc0, uint256 acc1, uint256 p0, uint256 p1) = _acc();
        assertEq(accounted, 1000e18);
        assertEq(acc0, 700e18);
        assertEq(acc1, 300e18);
        assertEq(p0, 700e18);
        assertEq(p1, 300e18);
        assertEq(token.balanceOf(address(split)), 1000e18, "release only accounts; tokens stay until withdrawn");
    }

    function test_Split_ReleaseEventExactTopicsAndData() public {
        token.mint(address(split), 1000e18);
        vm.recordLogs();
        split.release(t);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(split));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], ISplit.Released.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(address(token)))));
        assertEq(logs[0].data, abi.encode(uint256(700e18), uint256(300e18)));
    }

    function test_Split_WithdrawPaysEachPayeeItsShare() public {
        token.mint(address(split), 1000e18);
        split.release(t);

        vm.expectEmit(true, true, false, true, address(split));
        emit ISplit.Withdrawn(t, alice, 700e18);
        vm.prank(alice);
        assertEq(split.withdraw(t), 700e18);
        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(bob), 0, "bob has not withdrawn yet");
        assertEq(split.pending(t, alice), 0);
        assertEq(split.pending(t, bob), 300e18);

        vm.prank(bob);
        assertEq(split.withdraw(t), 300e18);
        assertEq(token.balanceOf(bob), 300e18);
        assertEq(token.balanceOf(address(split)), 0);
    }

    function test_Split_WithdrawAccountsForUnreleasedTokensItself() public {
        token.mint(address(split), 1000e18);
        vm.prank(bob);
        assertEq(split.withdraw(t), 300e18, "withdraw syncs first");
        assertEq(split.pending(t, alice), 700e18);
    }

    /// The first withdraw succeeds with the exact amount; a second one finds nothing.
    function test_Split_SecondWithdrawFindsNothing() public {
        token.mint(address(split), 1000e18);
        vm.prank(alice);
        assertEq(split.withdraw(t), 700e18, "first withdraw pays exactly 70%");
        assertEq(token.balanceOf(alice), 700e18);

        vm.prank(alice);
        vm.expectRevert(ISplit.NothingToWithdraw.selector);
        split.withdraw(t);
        assertEq(token.balanceOf(alice), 700e18, "not paid twice");
        assertEq(token.balanceOf(address(split)), 300e18, "bob's share untouched");

        vm.prank(bob);
        assertEq(split.withdraw(t), 300e18, "bob still gets exactly his share");
    }

    function test_Split_StrangerCannotWithdraw() public {
        token.mint(address(split), 1000e18);
        split.release(t);
        vm.prank(random);
        vm.expectRevert(abi.encodeWithSelector(ISplit.NotPayee.selector, random));
        split.withdraw(t);
        assertEq(token.balanceOf(random), 0);
        assertEq(split.pending(t, alice), 700e18);
    }

    function test_Split_InvalidTokenRejected() public {
        vm.expectRevert(ISplit.InvalidToken.selector);
        split.release(IERC20(address(0)));
        vm.prank(alice);
        vm.expectRevert(ISplit.InvalidToken.selector);
        split.withdraw(IERC20(address(0)));
    }

    // ------------------------------------------------------------ rounding
    function test_Split_OddAmountDustStaysAndIsFoldedIntoNextRelease() public {
        token.mint(address(split), 101);
        (uint256 a0, uint256 a1) = split.release(t);
        assertEq(a0, 70, "floor(70.7)");
        assertEq(a1, 30, "floor(30.3)");
        (uint256 accounted,,,,) = _acc();
        assertEq(accounted, 101);

        // Nothing new: a release never reverts and credits nothing.
        (a0, a1) = split.release(t);
        assertEq(a0, 0);
        assertEq(a1, 0);

        // One more unit: 102 * 70% = 71.4 -> 71, 102 * 30% = 30.6 -> 30.
        token.mint(address(split), 1);
        (a0, a1) = split.release(t);
        assertEq(a0, 1);
        assertEq(a1, 0);
        assertEq(split.pending(t, alice), 71);
        assertEq(split.pending(t, bob), 30);
        assertEq(token.balanceOf(address(split)), 102, "one unit of dust is still held");
    }

    function test_Split_OneWeiReleasesNeverRevertAndStayFair() public {
        for (uint256 i = 0; i < 200; i++) {
            token.mint(address(split), 1);
            split.release(t);
        }
        (uint256 accounted, uint256 a0, uint256 a1, uint256 p0, uint256 p1) = _acc();
        assertEq(accounted, 200);
        assertEq(a0, 140, "70% of 200, not starved by repeated rounding");
        assertEq(a1, 60, "30% of 200, not starved by repeated rounding");
        assertEq(p0, 140);
        assertEq(p1, 60);
    }

    function test_Split_ReleaseWithNothingNeverReverts() public {
        (uint256 a0, uint256 a1) = split.release(t);
        assertEq(a0, 0);
        assertEq(a1, 0);
    }

    struct Run {
        uint256 s0;
        uint256 s1;
        uint256 received;
        uint256 withdrawn0;
        uint256 withdrawn1;
    }

    /// Split math for odd amounts over many releases and interleaved withdrawals.
    function testFuzz_Split_ManyReleasesNeverOverpayAndStayWithinOneUnit(uint16 s0Seed, uint256 seed) public {
        Run memory r;
        r.s0 = bound(s0Seed, 1, 9999);
        r.s1 = 10_000 - r.s0;
        ISplit s = _newSplit(_pair(alice, bob), _bps(uint16(r.s0), uint16(r.s1)));

        for (uint256 i = 0; i < 40; i++) {
            uint256 h = uint256(keccak256(abi.encode(seed, i)));
            uint256 amount = i % 3 == 0 ? bound(h, 0, 100) : bound(h, 0, 1e30);
            if (amount != 0) {
                token.mint(address(s), amount);
                r.received += amount;
            }
            vm.prank(i % 2 == 0 ? random : carol);
            s.release(t);

            if (h % 5 == 0) {
                (r.withdrawn0, r.withdrawn1) = _maybeWithdraw(s, r.withdrawn0, r.withdrawn1, h);
            }
            _checkStep(s, r);
        }
    }

    function _checkStep(ISplit s, Run memory r) private view {
        (uint256 accounted, uint256 a0, uint256 a1, uint256 p0, uint256 p1) = s.ledger(t);
        assertEq(accounted, r.received, "everything received is accounted after a release");
        assertLe(a0 + a1, r.received, "never credits more than received");
        assertLe(r.received - a0 - a1, 1, "dust is at most one unit");
        // each side within one unit of its exact share of the cumulative inflow
        assertLe(a0 * 10_000, r.received * r.s0);
        assertLt(r.received * r.s0 - a0 * 10_000, 10_000);
        assertLe(a1 * 10_000, r.received * r.s1);
        assertLt(r.received * r.s1 - a1 * 10_000, 10_000);
        // solvency
        uint256 bal = token.balanceOf(address(s));
        assertEq(bal, r.received - r.withdrawn0 - r.withdrawn1, "balance == in - out");
        assertLe(p0 + p1, bal, "pending never exceeds the balance");
        assertEq(a0, p0 + r.withdrawn0);
        assertEq(a1, p1 + r.withdrawn1);
    }

    function _maybeWithdraw(ISplit s, uint256 w0, uint256 w1, uint256 h) private returns (uint256, uint256) {
        if (h % 2 == 0) {
            if (s.pending(t, alice) != 0) {
                vm.prank(alice);
                w0 += s.withdraw(t);
            }
        } else {
            if (s.pending(t, bob) != 0) {
                vm.prank(bob);
                w1 += s.withdraw(t);
            }
        }
        return (w0, w1);
    }

    function testFuzz_Split_SingleReleaseMatchesFloors(uint16 s0Seed, uint256 amount) public {
        uint16 s0 = uint16(bound(s0Seed, 1, 9999));
        amount = bound(amount, 0, type(uint128).max);
        ISplit s = _newSplit(_pair(alice, bob), _bps(s0, 10_000 - s0));
        token.mint(address(s), amount);
        (uint256 a0, uint256 a1) = s.release(t);
        assertEq(a0, Math.mulDiv(amount, s0, 10_000));
        assertEq(a1, Math.mulDiv(amount, 10_000 - s0, 10_000));
        assertLe(a0 + a1, amount);
        assertLe(amount - a0 - a1, 1);
    }

    // ------------------------------------------------------------ odd tokens
    /// A fee-on-transfer token: withdraw pays the payee less than its credit but never touches the
    /// other payee's funds.
    function test_Split_FeeOnTransferTokenDoesNotHurtTheOtherPayee() public {
        FeeToken fee = new FeeToken();
        IERC20 f = IERC20(address(fee));
        fee.mint(address(split), 1000e18);

        vm.prank(alice);
        assertEq(split.withdraw(f), 700e18, "credit is 700");
        assertEq(fee.balanceOf(alice), 693e18, "1% fee taken by the token");
        assertEq(fee.balanceOf(address(split)), 300e18);

        vm.prank(bob);
        assertEq(split.withdraw(f), 300e18);
        assertEq(fee.balanceOf(bob), 297e18);
        assertEq(fee.balanceOf(address(split)), 0);
    }

    function test_Split_TokensAreAccountedSeparately() public {
        MockERC20 other = new MockERC20();
        token.mint(address(split), 1000e18);
        other.mint(address(split), 50e18);
        split.release(t);
        split.release(IERC20(address(other)));
        assertEq(split.pending(t, alice), 700e18);
        assertEq(split.pending(IERC20(address(other)), alice), 35e18);
        assertEq(split.pending(IERC20(address(other)), bob), 15e18);
    }

    function test_Split_LaterDepositsAreSplitToo() public {
        token.mint(address(split), 100e18);
        vm.prank(alice);
        split.withdraw(t);
        assertEq(token.balanceOf(alice), 70e18);

        token.mint(address(split), 200e18);
        vm.prank(alice);
        assertEq(split.withdraw(t), 140e18);
        vm.prank(bob);
        assertEq(split.withdraw(t), 90e18, "30 from the first deposit + 60 from the second");
        assertEq(token.balanceOf(address(split)), 0);
    }
}
