// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {ISplitFactory} from "contracts/interfaces/ISplitFactory.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Nobody can change payees or shares, redirect funds, or send native value.
abstract contract SplitNoBackdoorSpec is SplitSpecBase {
    MockERC20 internal token;
    IERC20 internal t;
    ISplitFactory internal factory;
    ISplit internal split;
    address[5] internal actors;

    function setUp() public virtual {
        _initTime();
        token = new MockERC20();
        t = IERC20(address(token));
        vm.prank(creator);
        factory = _newSplitFactory();
        vm.prank(creator);
        split = ISplit(factory.createSplit(_pair(alice, bob), _bps(7000, 3000)));
        token.mint(address(split), 1000e18);
        actors = [creator, alice, bob, random, carol];
    }

    function _sigs() internal pure returns (string[44] memory s) {
        s = [
            "withdraw()",
            "withdraw(uint256)",
            "withdraw(address,uint256)",
            "withdrawTo(address,address)",
            "withdrawFor(address,address)",
            "rescue(address)",
            "rescueTokens(address,uint256)",
            "sweep(address)",
            "emergencyWithdraw(address)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "setPayee(uint256,address)",
            "setPayees(address,address)",
            "setPayee0(address)",
            "setPayee1(address)",
            "setShares(uint16,uint16)",
            "setShares(uint16[2])",
            "updatePayee(address)",
            "changePayee(address)",
            "transferPayee(address)",
            "setFee(uint256)",
            "setFeeRecipient(address)",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize()",
            "initialize(address[2],uint16[2])",
            "init(address[2],uint16[2])",
            "multicall(bytes[])",
            "execute(address,uint256,bytes)",
            "call(address,bytes)",
            "delegatecall(address,bytes)",
            "selfdestruct(address)",
            "mint(address,uint256)",
            "transfer(address,uint256)",
            "approve(address,uint256)",
            "releaseTo(address,address)",
            "releaseNative()",
            "release()",
            "release(address,address)",
            "deposit()",
            "claim(address)"
        ];
    }

    function _snapshot() internal view returns (bytes32) {
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) = split.ledger(t);
        bytes32 config =
            keccak256(abi.encode(split.payee0(), split.payee1(), split.shares0(), split.shares1(), a, b, c, d, e));
        bytes32 money = keccak256(
            abi.encode(
                token.balanceOf(address(split)),
                token.balanceOf(alice),
                token.balanceOf(bob),
                token.balanceOf(random),
                token.balanceOf(creator),
                address(split).balance,
                address(factory).balance,
                factory.splitCount()
            )
        );
        return keccak256(abi.encode(config, money));
    }

    function test_SplitNoBackdoor_AdminSelectorsAllRevertForEveryActor() public {
        string[44] memory sigs = _sigs();
        address[2] memory targets = [address(split), address(factory)];
        bytes32 before = _snapshot();
        for (uint256 ti = 0; ti < targets.length; ti++) {
            for (uint256 a = 0; a < actors.length; a++) {
                for (uint256 s = 0; s < sigs.length; s++) {
                    bytes memory data = abi.encodePacked(bytes4(keccak256(bytes(sigs[s]))), new bytes(192));
                    vm.prank(actors[a]);
                    (bool ok,) = targets[ti].call(data);
                    assertFalse(ok, string.concat("must revert: ", sigs[s]));
                }
            }
        }
        assertEq(_snapshot(), before, "nothing changed");
    }

    function test_SplitNoBackdoor_NativeValueCannotBeSent() public {
        address[2] memory targets = [address(split), address(factory)];
        bytes32 before = _snapshot();
        for (uint256 ti = 0; ti < targets.length; ti++) {
            for (uint256 a = 0; a < actors.length; a++) {
                vm.deal(actors[a], 10 ether);
                vm.prank(actors[a]);
                (bool ok,) = targets[ti].call("");
                assertFalse(ok, "empty calldata reverts (no fallback)");
                vm.prank(actors[a]);
                (ok,) = targets[ti].call{value: 1 wei}("");
                assertFalse(ok, "plain native transfer reverts (no receive)");
                vm.prank(actors[a]);
                (ok,) = targets[ti].call{value: 1 wei}(hex"deadbeef");
                assertFalse(ok, "unknown selector with value reverts");
                vm.prank(actors[a]);
                (ok,) = targets[ti].call(hex"aabbcc");
                assertFalse(ok, "short calldata reverts");
            }
            assertEq(targets[ti].balance, 0, "no native value ever lands");
        }
        // Valid functions are not payable either.
        vm.deal(random, 1 ether);
        vm.startPrank(random);
        (bool ok2,) = address(split).call{value: 1 wei}(abi.encodeCall(ISplit.release, (t)));
        assertFalse(ok2, "release is not payable");
        (ok2,) = address(factory).call{value: 1 wei}(abi.encodeCall(ISplitFactory.createSplit, (_pair(alice, bob), _bps(5000, 5000))));
        assertFalse(ok2, "createSplit is not payable");
        vm.stopPrank();
        assertEq(_snapshot(), before, "nothing changed");
    }

    /// Whatever anyone does, payees and shares are the same afterwards, and only release/withdraw move money.
    function test_SplitNoBackdoor_ConfigurationNeverChanges() public {
        test_SplitNoBackdoor_AdminSelectorsAllRevertForEveryActor();
        test_SplitNoBackdoor_NativeValueCannotBeSent();

        vm.prank(random);
        split.release(t);
        vm.prank(alice);
        split.withdraw(t);
        vm.prank(bob);
        split.withdraw(t);
        token.mint(address(split), 77);
        vm.prank(creator);
        split.release(t);

        assertEq(split.payee0(), alice);
        assertEq(split.payee1(), bob);
        assertEq(split.shares0(), 7000);
        assertEq(split.shares1(), 3000);
        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(bob), 300e18);
        assertEq(token.balanceOf(random), 0);
        assertEq(token.balanceOf(creator), 0);
        assertEq(token.balanceOf(address(split)), 77);
    }

    /// Everything a stranger or the creator can do is the same: release credits the payees, nothing else.
    function test_SplitNoBackdoor_ReleaseIsIdenticalForEveryCaller() public {
        for (uint256 a = 0; a < actors.length; a++) {
            uint256 snap = vm.snapshotState();
            vm.prank(actors[a]);
            (uint256 a0, uint256 a1) = split.release(t);
            assertEq(a0, 700e18);
            assertEq(a1, 300e18);
            assertEq(split.pending(t, alice), 700e18);
            assertEq(split.pending(t, bob), 300e18);
            assertEq(token.balanceOf(actors[a]), 0, "the caller is not paid");
            vm.revertToState(snap);
        }
    }
}
