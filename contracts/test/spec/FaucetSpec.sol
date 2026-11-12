// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Behaviour of a DripFaucet. Runs against whatever `_newFaucet` returns.
abstract contract FaucetSpec is SpecBase {
    uint256 internal constant CLAIM = 10e18;
    uint64 internal constant COOLDOWN = 8 hours;

    MockERC20 internal token;
    IDripFaucet internal faucet;

    function setUp() public virtual {
        _initTime();
        token = new MockERC20();
        faucet = _newFaucet(IERC20(address(token)), CLAIM, COOLDOWN);
        token.mint(address(faucet), 100e18);
    }

    function test_Faucet_Immutables() public view {
        assertEq(address(faucet.token()), address(token));
        assertEq(faucet.claimAmount(), CLAIM);
        assertEq(faucet.cooldown(), COOLDOWN);
        assertEq(faucet.nextClaimAt(alice), 0);
        assertEq(faucet.lastClaim(alice), 0);
    }

    function test_Faucet_ClaimPaysExactAmountToCaller() public {
        vm.prank(alice);
        uint256 got = faucet.claim();
        assertEq(got, CLAIM, "return value");
        assertEq(token.balanceOf(alice), CLAIM, "alice balance");
        assertEq(token.balanceOf(address(faucet)), 100e18 - CLAIM, "faucet balance");
        assertEq(faucet.nextClaimAt(alice), T0 + COOLDOWN, "nextClaimAt");
        assertEq(faucet.lastClaim(alice), T0, "lastClaim");
        assertEq(faucet.nextClaimAt(bob), 0, "bob untouched");
    }

    /// Case 5: the cooldown is enforced per address.
    function test_Faucet_CooldownIsEnforcedPerAddress() public {
        vm.prank(alice);
        assertEq(faucet.claim(), CLAIM, "first claim pays exactly claimAmount");

        uint256 t = block.timestamp;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownActive.selector, t + COOLDOWN));
        faucet.claim();
        assertEq(token.balanceOf(alice), CLAIM, "alice was not paid twice");

        // B can claim in the very same block.
        vm.prank(bob);
        assertEq(faucet.claim(), CLAIM, "bob claims in the same block");
        assertEq(token.balanceOf(bob), CLAIM);
        assertEq(faucet.nextClaimAt(bob), t + COOLDOWN);
    }

    function test_Faucet_CooldownBoundary() public {
        vm.prank(alice);
        assertEq(faucet.claim(), CLAIM, "first claim pays exactly claimAmount");
        uint256 t = block.timestamp;

        vm.warp(t + COOLDOWN - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownActive.selector, t + COOLDOWN));
        faucet.claim();

        vm.warp(t + COOLDOWN);
        vm.prank(alice);
        assertEq(faucet.claim(), CLAIM, "claim succeeds at exactly t + cooldown");
        assertEq(token.balanceOf(alice), 2 * CLAIM);
        assertEq(faucet.nextClaimAt(alice), t + 2 * COOLDOWN);
        assertEq(faucet.lastClaim(alice), t + COOLDOWN);
    }

    /// Case 6: an empty faucet reverts and does not consume the cooldown.
    function test_Faucet_EmptyFaucetRevertsWithoutSideEffects() public {
        IDripFaucet empty = _newFaucet(IERC20(address(token)), CLAIM, COOLDOWN);
        vm.recordLogs();
        vm.prank(alice);
        vm.expectRevert(IDripFaucet.FaucetEmpty.selector);
        empty.claim();
        assertEq(empty.nextClaimAt(alice), 0, "cooldown not consumed");
        assertEq(token.balanceOf(alice), 0);
        assertEq(vm.getRecordedLogs().length, 0, "no event");

        // Funding it afterwards lets the same caller claim right away.
        token.mint(address(empty), CLAIM);
        vm.prank(alice);
        assertEq(empty.claim(), CLAIM);
        assertEq(token.balanceOf(alice), CLAIM);
    }

    function test_Faucet_PartialBalancePaysExactlyTheBalance() public {
        IDripFaucet small = _newFaucet(IERC20(address(token)), CLAIM, COOLDOWN);
        token.mint(address(small), 3e18);

        vm.prank(alice);
        assertEq(small.claim(), 3e18, "pays exactly the balance");
        assertEq(token.balanceOf(alice), 3e18);
        assertEq(token.balanceOf(address(small)), 0);
        assertEq(small.nextClaimAt(alice), T0 + COOLDOWN, "a paid partial claim does consume the cooldown");

        // Now empty: another address reverts FaucetEmpty, state unchanged.
        vm.prank(bob);
        vm.expectRevert(IDripFaucet.FaucetEmpty.selector);
        small.claim();
        assertEq(small.nextClaimAt(bob), 0);
    }

    function test_Faucet_ClaimedEvent() public {
        vm.expectEmit(true, false, false, true, address(faucet));
        emit IDripFaucet.Claimed(alice, CLAIM);
        vm.prank(alice);
        faucet.claim();

        // Partial payout: the event shows what was actually sent.
        IDripFaucet small = _newFaucet(IERC20(address(token)), CLAIM, COOLDOWN);
        token.mint(address(small), 4e18);
        vm.expectEmit(true, false, false, true, address(small));
        emit IDripFaucet.Claimed(bob, 4e18);
        vm.prank(bob);
        small.claim();
    }

    function test_Faucet_ClaimedEventExactTopicsAndData() public {
        vm.recordLogs();
        vm.prank(alice);
        faucet.claim();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // token Transfer + Claimed
        assertEq(logs.length, 2);
        Vm.Log memory l = logs[1];
        assertEq(l.emitter, address(faucet));
        assertEq(l.topics.length, 2);
        assertEq(l.topics[0], IDripFaucet.Claimed.selector);
        assertEq(l.topics[1], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(l.data, (uint256)), CLAIM);
    }

    /// Cooldown of type(uint64).max means "claim once ever".
    function test_Faucet_ClaimOnceEver() public {
        IDripFaucet once = _newFaucet(IERC20(address(token)), CLAIM, type(uint64).max);
        token.mint(address(once), 100e18);
        vm.prank(alice);
        assertEq(once.claim(), CLAIM);
        uint256 next = T0 + uint256(type(uint64).max);
        assertEq(once.nextClaimAt(alice), next);
        assertEq(once.lastClaim(alice), T0);

        vm.warp(T0 + 100 * 365 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownActive.selector, next));
        once.claim();
    }

    function test_Faucet_ConstructorRejectsBadParameters() public {
        vm.expectRevert(IDripFaucet.InvalidToken.selector);
        _newFaucet(IERC20(address(0)), CLAIM, COOLDOWN);

        vm.expectRevert(IDripFaucet.InvalidClaimAmount.selector);
        _newFaucet(IERC20(address(token)), 0, COOLDOWN);

        vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownTooShort.selector, uint64(59)));
        _newFaucet(IERC20(address(token)), CLAIM, 59);

        vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownTooShort.selector, uint64(0)));
        _newFaucet(IERC20(address(token)), CLAIM, 0);
    }

    function test_Faucet_ConstructorAcceptsBoundaries() public {
        IDripFaucet a = _newFaucet(IERC20(address(token)), 1, 60);
        assertEq(a.cooldown(), 60);
        assertEq(a.claimAmount(), 1);
        IDripFaucet b = _newFaucet(IERC20(address(token)), type(uint256).max, type(uint64).max);
        assertEq(b.cooldown(), type(uint64).max);
        assertEq(b.claimAmount(), type(uint256).max);
    }
}
