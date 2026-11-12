// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {ISplitFactory} from "contracts/interfaces/ISplitFactory.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Behaviour of the factory. Runs against whatever `_newSplitFactory` returns.
abstract contract SplitFactorySpec is SplitSpecBase {
    ISplitFactory internal factory;

    function setUp() public virtual {
        _initTime();
        vm.prank(creator);
        factory = _newSplitFactory();
    }

    function _create(address a, address b, uint16 s0, uint16 s1) internal returns (address) {
        vm.prank(creator);
        return factory.createSplit(_pair(a, b), _bps(s0, s1));
    }

    function test_Factory_CreatesSplitWithFixedConfiguration() public {
        address s = _create(alice, bob, 7000, 3000);
        assertTrue(s != address(0));
        assertTrue(factory.isSplit(s));
        assertEq(ISplit(s).payee0(), alice);
        assertEq(ISplit(s).payee1(), bob);
        assertEq(ISplit(s).shares0(), 7000);
        assertEq(ISplit(s).shares1(), 3000);
        assertEq(factory.splitCount(), 1);
        assertEq(factory.splits(0), s);
    }

    function test_Factory_SplitCreatedEventExactTopicsAndData() public {
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));
        vm.expectEmit(true, false, true, true, address(factory));
        emit ISplitFactory.SplitCreated(predicted, _pair(alice, bob), _bps(7000, 3000), creator);
        address s = _create(alice, bob, 7000, 3000);
        assertEq(s, predicted);
    }

    function test_Factory_SplitCreatedRawLog() public {
        vm.recordLogs();
        address s = _create(alice, bob, 7000, 3000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(factory));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], ISplitFactory.SplitCreated.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(s))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(creator))));
        assertEq(logs[0].data, abi.encode(_pair(alice, bob), _bps(7000, 3000)));
    }

    function test_Factory_ListAndEnumeration() public {
        assertEq(factory.splitCount(), 0);
        vm.expectRevert(abi.encodeWithSelector(ISplitFactory.UnknownSplit.selector, uint256(0)));
        factory.splits(0);

        address s0 = _create(alice, bob, 7000, 3000);
        address s1 = _create(alice, bob, 7000, 3000); // same configuration is allowed: distinct split
        address s2 = _create(bob, carol, 1, 9999);
        assertEq(factory.splitCount(), 3);
        assertEq(factory.splits(0), s0);
        assertEq(factory.splits(1), s1);
        assertEq(factory.splits(2), s2);
        assertTrue(s0 != s1 && s1 != s2);
        assertTrue(factory.isSplit(s2));
        assertFalse(factory.isSplit(alice));
        assertFalse(factory.isSplit(address(factory)));

        vm.expectRevert(abi.encodeWithSelector(ISplitFactory.UnknownSplit.selector, uint256(3)));
        factory.splits(3);
        vm.expectRevert(abi.encodeWithSelector(ISplitFactory.UnknownSplit.selector, type(uint256).max));
        factory.splits(type(uint256).max);
    }

    function test_Factory_AnyoneCanCreateAndCreatorHasNoPowers() public {
        vm.prank(random);
        address s = factory.createSplit(_pair(alice, bob), _bps(5000, 5000));
        // The creator is only recorded in the event; it is not a payee and cannot withdraw.
        MockERC20 token = new MockERC20();
        token.mint(s, 100e18);
        vm.prank(random);
        vm.expectRevert(abi.encodeWithSelector(ISplit.NotPayee.selector, random));
        ISplit(s).withdraw(IERC20(address(token)));
    }

    // validation errors bubble up from the Split constructor
    function test_Factory_RejectsZeroPayee() public {
        vm.prank(creator);
        vm.expectRevert(ISplit.ZeroPayee.selector);
        factory.createSplit(_pair(address(0), bob), _bps(7000, 3000));
    }

    function test_Factory_RejectsDuplicatePayees() public {
        vm.prank(creator);
        vm.expectRevert(ISplit.DuplicatePayees.selector);
        factory.createSplit(_pair(bob, bob), _bps(7000, 3000));
    }

    function test_Factory_RejectsZeroShare() public {
        vm.prank(creator);
        vm.expectRevert(ISplit.ZeroShare.selector);
        factory.createSplit(_pair(alice, bob), _bps(0, 10_000));
    }

    function test_Factory_RejectsSharesNotSummingTo10000() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ISplit.SharesDoNotSumToBasisPoints.selector, uint256(10_001)));
        factory.createSplit(_pair(alice, bob), _bps(7000, 3001));
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ISplit.SharesDoNotSumToBasisPoints.selector, uint256(9_999)));
        factory.createSplit(_pair(alice, bob), _bps(7000, 2999));
        assertEq(factory.splitCount(), 0, "a rejected creation leaves no trace");
    }

    function test_Factory_CreatedSplitWorksEndToEnd() public {
        address s = _create(alice, bob, 7000, 3000);
        MockERC20 token = new MockERC20();
        token.mint(s, 1000e18);
        ISplit(s).release(IERC20(address(token)));
        vm.prank(alice);
        assertEq(ISplit(s).withdraw(IERC20(address(token))), 700e18);
        vm.prank(bob);
        assertEq(ISplit(s).withdraw(IERC20(address(token))), 300e18);
    }
}
