// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Case 8 (b), (c), (d): nobody can withdraw or change anything.
abstract contract NoBackdoorSpec is SpecBase {
    uint256 internal constant AMOUNT = 100_000e18;
    uint16 internal constant BPS = 100;
    uint64 internal constant PERIOD = 1 days;
    uint256 internal constant CLAIM = 10e18;
    uint64 internal constant COOLDOWN = 8 hours;

    MockERC20 internal token;
    IDripLaunchpad internal lp;
    IDripVault internal vault;
    IDripFaucet internal faucet;
    address[3] internal actors;

    function setUp() public virtual {
        _initTime();
        vm.prank(deployer);
        lp = _newLaunchpad();
        token = new MockERC20();
        token.mint(launcher, AMOUNT);
        vm.startPrank(launcher);
        token.approve(address(lp), AMOUNT);
        (, address v, address f) = lp.launch(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
        vm.stopPrank();
        vault = IDripVault(v);
        faucet = IDripFaucet(f);
        actors = [launcher, deployer, random];
    }

    // ------------------------------------------------------------ helpers
    function _targets() internal view returns (address[3] memory) {
        return [address(lp), address(vault), address(faucet)];
    }

    function _viewCalls() internal view returns (address[] memory targets, bytes[] memory datas) {
        targets = new address[](12);
        datas = new bytes[](12);
        targets[0] = address(lp);
        datas[0] = abi.encodeCall(IDripLaunchpad.launchCount, ());
        targets[1] = address(lp);
        datas[1] = abi.encodeCall(IDripLaunchpad.launches, (0));
        targets[2] = address(vault);
        datas[2] = abi.encodeCall(IDripVault.token, ());
        targets[3] = address(vault);
        datas[3] = abi.encodeCall(IDripVault.faucet, ());
        targets[4] = address(vault);
        datas[4] = abi.encodeCall(IDripVault.dripBps, ());
        targets[5] = address(vault);
        datas[5] = abi.encodeCall(IDripVault.period, ());
        targets[6] = address(vault);
        datas[6] = abi.encodeCall(IDripVault.nextDripAt, ());
        targets[7] = address(faucet);
        datas[7] = abi.encodeCall(IDripFaucet.token, ());
        targets[8] = address(faucet);
        datas[8] = abi.encodeCall(IDripFaucet.claimAmount, ());
        targets[9] = address(faucet);
        datas[9] = abi.encodeCall(IDripFaucet.cooldown, ());
        targets[10] = address(faucet);
        datas[10] = abi.encodeCall(IDripFaucet.nextClaimAt, (alice));
        targets[11] = address(faucet);
        datas[11] = abi.encodeCall(IDripFaucet.lastClaim, (alice));
    }

    function _adminSignatures() internal pure returns (string[40] memory s) {
        s = [
            "withdraw()",
            "withdraw(uint256)",
            "withdraw(address,uint256)",
            "rescue()",
            "rescue(address,uint256)",
            "rescueTokens(address,uint256)",
            "rescueTokens(address,address,uint256)",
            "sweep()",
            "sweep(address)",
            "emergencyWithdraw()",
            "emergencyWithdraw(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "setDripBps(uint16)",
            "setPeriod(uint64)",
            "setClaimAmount(uint256)",
            "setCooldown(uint64)",
            "setFaucet(address)",
            "setFee(uint256)",
            "setFee(uint16)",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize()",
            "initialize(address)",
            "claimFor(address)",
            "multicall(bytes[])",
            "execute(address,uint256,bytes)",
            "mint(address,uint256)",
            "transfer(address,uint256)",
            "approve(address,uint256)",
            "transferFrom(address,address,uint256)",
            "selfdestruct()",
            "setToken(address)",
            "setOwner(address)",
            "grantRole(bytes32,address)",
            "drip(uint256)",
            "claim(address)"
        ];
    }

    function _snapshotHash() internal view returns (bytes32) {
        return keccak256(abi.encode(_configHash(), _clockHash(), _balanceHash()));
    }

    function _configHash() private view returns (bytes32) {
        (address v, address f) = lp.launches(0);
        return keccak256(
            abi.encode(
                lp.launchCount(),
                v,
                f,
                address(vault.token()),
                vault.faucet(),
                vault.dripBps(),
                vault.period(),
                address(faucet.token()),
                faucet.claimAmount(),
                faucet.cooldown()
            )
        );
    }

    function _clockHash() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                vault.nextDripAt(), faucet.nextClaimAt(launcher), faucet.nextClaimAt(deployer), faucet.nextClaimAt(random)
            )
        );
    }

    function _balanceHash() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                token.balanceOf(address(lp)),
                token.balanceOf(address(vault)),
                token.balanceOf(address(faucet)),
                token.balanceOf(launcher),
                token.balanceOf(deployer),
                token.balanceOf(random),
                address(lp).balance,
                address(vault).balance,
                address(faucet).balance
            )
        );
    }

    // ------------------------------------------------------------- (b)
    /// Every view returns the same bytes to the launcher, the factory deployer and a random address.
    function test_NoBackdoor_ViewsAreIdenticalForEveryActor() public {
        (address[] memory targets, bytes[] memory datas) = _viewCalls();
        for (uint256 i = 0; i < targets.length; i++) {
            bytes32 first;
            for (uint256 a = 0; a < actors.length; a++) {
                vm.prank(actors[a]);
                (bool ok, bytes memory ret) = targets[i].staticcall(datas[i]);
                assertTrue(ok, "view call succeeds");
                if (a == 0) first = keccak256(ret);
                else assertEq(keccak256(ret), first, "view result is actor independent");
            }
        }
    }

    /// drip(): the launcher, the deployer and a stranger all get the same thing: the faucet is paid,
    /// the caller is not.
    function test_NoBackdoor_DripIsIdenticalForEveryActor() public {
        for (uint256 a = 0; a < actors.length; a++) {
            uint256 snap = vm.snapshotState();
            uint256 callerBefore = token.balanceOf(actors[a]);
            vm.prank(actors[a]);
            assertEq(vault.drip(), 1_000e18, "drip pays exactly 1%");
            assertEq(token.balanceOf(address(faucet)), 1_000e18, "the faucet is paid");
            assertEq(token.balanceOf(address(vault)), AMOUNT - 1_000e18);
            assertEq(token.balanceOf(actors[a]), callerBefore, "the caller is not paid");
            assertEq(vault.nextDripAt(), T0 + PERIOD);
            vm.revertToState(snap);
        }
    }

    /// claim(): everyone gets exactly claimAmount for themselves, under the same cooldown.
    function test_NoBackdoor_ClaimIsIdenticalForEveryActor() public {
        vault.drip(); // fund the faucet
        for (uint256 a = 0; a < actors.length; a++) {
            uint256 snap = vm.snapshotState();
            address who = actors[a];
            uint256 before = token.balanceOf(who);
            uint256 faucetBefore = token.balanceOf(address(faucet));

            vm.prank(who);
            assertEq(faucet.claim(), CLAIM, "claim pays exactly claimAmount");
            assertEq(token.balanceOf(who), before + CLAIM);
            assertEq(token.balanceOf(address(faucet)), faucetBefore - CLAIM);
            assertEq(faucet.nextClaimAt(who), T0 + COOLDOWN);
            for (uint256 o = 0; o < actors.length; o++) {
                if (o != a) assertEq(faucet.nextClaimAt(actors[o]), 0, "others' cooldown untouched");
            }

            vm.prank(who);
            vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownActive.selector, T0 + COOLDOWN));
            faucet.claim();
            vm.revertToState(snap);
        }
    }

    /// launch(): it only ever spends the caller's own allowance and balance.
    function test_NoBackdoor_LaunchSpendsOnlyTheCallersOwnTokens() public {
        // launcher approves again; a stranger and the deployer still cannot use it.
        vm.prank(launcher);
        token.approve(address(lp), AMOUNT);
        token.mint(launcher, AMOUNT);
        for (uint256 a = 1; a < actors.length; a++) {
            vm.prank(actors[a]);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(lp), 0, AMOUNT)
            );
            lp.launch(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
        }
        assertEq(token.balanceOf(launcher), AMOUNT);
    }

    // ------------------------------------------------------------- (c)
    function test_NoBackdoor_AdminSelectorsAllRevertForEveryActor() public {
        string[40] memory sigs = _adminSignatures();
        address[3] memory targets = _targets();
        bytes32 before = _snapshotHash();
        for (uint256 t = 0; t < targets.length; t++) {
            for (uint256 a = 0; a < actors.length; a++) {
                for (uint256 s = 0; s < sigs.length; s++) {
                    // selector + 4 zero words: enough for every signature above.
                    bytes memory data = abi.encodePacked(bytes4(keccak256(bytes(sigs[s]))), new bytes(128));
                    vm.prank(actors[a]);
                    (bool ok,) = targets[t].call(data);
                    assertFalse(ok, string.concat("must revert: ", sigs[s]));
                }
            }
        }
        assertEq(_snapshotHash(), before, "nothing changed");
    }

    function test_NoBackdoor_EmptyCalldataAndValueAllRevert() public {
        address[3] memory targets = _targets();
        bytes32 before = _snapshotHash();
        for (uint256 t = 0; t < targets.length; t++) {
            for (uint256 a = 0; a < actors.length; a++) {
                vm.deal(actors[a], 10 ether);
                // empty calldata, no value (no fallback)
                vm.prank(actors[a]);
                (bool ok,) = targets[t].call("");
                assertFalse(ok, "empty calldata reverts");
                // plain ETH transfer (no receive)
                vm.prank(actors[a]);
                (ok,) = targets[t].call{value: 1 wei}("");
                assertFalse(ok, "ETH transfer reverts");
                // junk calldata with value
                vm.prank(actors[a]);
                (ok,) = targets[t].call{value: 1 wei}(hex"deadbeef");
                assertFalse(ok, "junk calldata with value reverts");
                // 1-3 byte calldata
                vm.prank(actors[a]);
                (ok,) = targets[t].call(hex"aabbcc");
                assertFalse(ok, "short calldata reverts");
            }
            assertEq(targets[t].balance, 0, "no ETH ever lands");
        }
        assertEq(_snapshotHash(), before, "nothing changed");
    }

    function test_NoBackdoor_ValidFunctionsRejectValue() public {
        vm.deal(random, 10 ether);
        vm.startPrank(random);
        (bool ok,) = address(vault).call{value: 1 wei}(abi.encodeCall(IDripVault.drip, ()));
        assertFalse(ok, "drip is not payable");
        (ok,) = address(faucet).call{value: 1 wei}(abi.encodeCall(IDripFaucet.claim, ()));
        assertFalse(ok, "claim is not payable");
        (ok,) = address(lp).call{value: 1 wei}(
            abi.encodeCall(IDripLaunchpad.launch, (IERC20(address(token)), 1, BPS, PERIOD, CLAIM, COOLDOWN))
        );
        assertFalse(ok, "launch is not payable");
        (ok,) = address(vault).call{value: 1 wei}(abi.encodeCall(IDripVault.nextDripAt, ()));
        assertFalse(ok, "views are not payable");
        vm.stopPrank();
        assertEq(address(vault).balance + address(faucet).balance + address(lp).balance, 0);
    }

    // ------------------------------------------------------------- (d)
    /// After the probes only the legitimate drip/claim calls changed anything.
    function test_NoBackdoor_ParametersAndBalancesUnchangedExceptByDripAndClaim() public {
        bytes32 before = _snapshotHash();
        // Probe everything first.
        test_NoBackdoor_AdminSelectorsAllRevertForEveryActor();
        test_NoBackdoor_EmptyCalldataAndValueAllRevert();
        assertEq(_snapshotHash(), before);

        // Then the legitimate calls: they alone move tokens and clocks.
        vault.drip();
        vm.prank(alice);
        faucet.claim();
        assertEq(token.balanceOf(address(vault)), AMOUNT - 1_000e18);
        assertEq(token.balanceOf(address(faucet)), 1_000e18 - CLAIM);
        assertEq(token.balanceOf(alice), CLAIM);
        assertEq(vault.dripBps(), BPS);
        assertEq(vault.period(), PERIOD);
        assertEq(faucet.claimAmount(), CLAIM);
        assertEq(faucet.cooldown(), COOLDOWN);
        assertEq(vault.faucet(), address(faucet));
        assertEq(lp.launchCount(), 1);
    }
}
