// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";
import {FeeToken} from "contracts/test/mocks/FeeToken.sol";
import {NoOpTransferFromToken} from "contracts/test/mocks/NoOpTransferFromToken.sol";

/// @dev Behaviour of the factory (and of the vault and faucet it creates). Runs against `_newLaunchpad`.
abstract contract LaunchpadSpec is SpecBase {
    uint256 internal constant AMOUNT = 100_000e18;
    uint16 internal constant BPS = 100;
    uint64 internal constant PERIOD = 1 days;
    uint256 internal constant CLAIM = 10e18;
    uint64 internal constant COOLDOWN = 8 hours;

    IDripLaunchpad internal lp;
    MockERC20 internal token;

    function setUp() public virtual {
        _initTime();
        vm.prank(deployer);
        lp = _newLaunchpad();
        token = new MockERC20();
        token.mint(launcher, 10 * AMOUNT);
        vm.prank(launcher);
        token.approve(address(lp), type(uint256).max);
    }

    function _launch() internal returns (uint256 id, address vault, address faucet) {
        vm.prank(launcher);
        return lp.launch(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
    }

    function _launchRaw(IERC20 t, uint256 amount, uint16 bps, uint64 period, uint256 claim_, uint64 cooldown)
        internal
        returns (uint256, address, address)
    {
        vm.prank(launcher);
        return lp.launch(t, amount, bps, period, claim_, cooldown);
    }

    // ---------------------------------------------------------------- case 1
    function test_Launchpad_FullFlow() public {
        (uint256 id, address vaultAddr, address faucetAddr) = _launch();
        IDripVault vault = IDripVault(vaultAddr);
        IDripFaucet faucet = IDripFaucet(faucetAddr);
        assertEq(id, 0);
        assertEq(token.balanceOf(address(lp)), 0, "the factory never holds tokens");
        assertEq(token.balanceOf(vaultAddr), AMOUNT);
        assertEq(token.balanceOf(launcher), 9 * AMOUNT);
        assertEq(vault.nextDripAt(), T0, "first drip is available at launch");
        assertEq(vault.faucet(), faucetAddr);

        // Drip immediately.
        assertEq(vault.drip(), 1_000e18, "1% of 100,000");
        assertEq(token.balanceOf(vaultAddr), 99_000e18);
        assertEq(token.balanceOf(faucetAddr), 1_000e18);
        assertEq(vault.nextDripAt(), T0 + PERIOD);

        // Claims by A and B.
        vm.prank(alice);
        assertEq(faucet.claim(), CLAIM);
        vm.prank(bob);
        assertEq(faucet.claim(), CLAIM);
        assertEq(token.balanceOf(alice), CLAIM);
        assertEq(token.balanceOf(bob), CLAIM);
        assertEq(token.balanceOf(faucetAddr), 980e18);
        assertEq(faucet.nextClaimAt(alice), T0 + COOLDOWN);
        assertEq(faucet.nextClaimAt(bob), T0 + COOLDOWN);

        // Warp one period, drip again.
        vm.warp(T0 + PERIOD);
        assertEq(vault.drip(), 990e18, "1% of 99,000");
        assertEq(token.balanceOf(vaultAddr), 98_010e18);
        assertEq(token.balanceOf(faucetAddr), 1_970e18);
        assertEq(vault.nextDripAt(), T0 + 2 * PERIOD);

        // Warp one cooldown, claim again.
        vm.warp(T0 + PERIOD + COOLDOWN);
        vm.prank(alice);
        assertEq(faucet.claim(), CLAIM);
        assertEq(token.balanceOf(alice), 2 * CLAIM);
        assertEq(token.balanceOf(bob), CLAIM);
        assertEq(token.balanceOf(faucetAddr), 1_960e18);
        assertEq(faucet.nextClaimAt(alice), T0 + PERIOD + 2 * COOLDOWN);
        assertEq(faucet.nextClaimAt(bob), T0 + COOLDOWN, "bob unchanged");

        // Conservation.
        assertEq(
            token.balanceOf(vaultAddr) + token.balanceOf(faucetAddr) + token.balanceOf(alice) + token.balanceOf(bob),
            AMOUNT
        );
    }

    function test_Launchpad_CreatesConfiguredVaultAndFaucet() public {
        (, address vaultAddr, address faucetAddr) = _launch();
        IDripVault vault = IDripVault(vaultAddr);
        IDripFaucet faucet = IDripFaucet(faucetAddr);
        assertEq(address(vault.token()), address(token));
        assertEq(vault.dripBps(), BPS);
        assertEq(vault.period(), PERIOD);
        assertEq(vault.faucet(), faucetAddr);
        assertEq(address(faucet.token()), address(token));
        assertEq(faucet.claimAmount(), CLAIM);
        assertEq(faucet.cooldown(), COOLDOWN);
    }

    /// @dev Expect `Launched` with ALL topics and data checked. The vault and faucet addresses are
    /// predicted from the factory's nonce (faucet first, then vault).
    function _expectLaunched(uint256 id, address tkn, uint256 received) internal {
        uint64 n = vm.getNonce(address(lp));
        vm.expectEmit(true, true, true, true, address(lp));
        emit IDripLaunchpad.Launched(
            id,
            tkn,
            vm.computeCreateAddress(address(lp), n + 1),
            vm.computeCreateAddress(address(lp), n),
            launcher,
            received,
            BPS,
            PERIOD,
            CLAIM,
            COOLDOWN
        );
    }

    // --------------------------------------------------------------- case 10
    function test_Launchpad_LaunchedEvent() public {
        _expectLaunched(0, address(token), AMOUNT);
        (uint256 id, address vault, address faucet) = _launch();
        assertEq(id, 0);
        assertEq(vault, vm.computeCreateAddress(address(lp), vm.getNonce(address(lp)) - 1));
        assertEq(faucet, vm.computeCreateAddress(address(lp), vm.getNonce(address(lp)) - 2));

        // A second launch carries id 1.
        _expectLaunched(1, address(token), AMOUNT);
        (id,,) = _launch();
        assertEq(id, 1);
    }

    function test_Launchpad_LaunchedEventExactTopicsAndData() public {
        vm.recordLogs();
        (, address vault, address faucet) = _launch();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory l = logs[logs.length - 1];
        assertEq(l.emitter, address(lp));
        assertEq(l.topics.length, 4);
        assertEq(l.topics[0], IDripLaunchpad.Launched.selector);
        assertEq(l.topics[1], bytes32(uint256(0)));
        assertEq(l.topics[2], bytes32(uint256(uint160(address(token)))));
        assertEq(l.topics[3], bytes32(uint256(uint160(launcher))));
        assertEq(l.data, abi.encode(vault, faucet, AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN));
    }

    // ---------------------------------------------------------------- case 7
    function test_Launchpad_FeeOnTransferCreditsOnlyWhatArrived() public {
        FeeToken fee = new FeeToken();
        fee.mint(launcher, AMOUNT);
        vm.prank(launcher);
        fee.approve(address(lp), type(uint256).max);

        uint256 arrived = 99_000e18; // 1% fee burned on the single transfer launcher -> vault
        _expectLaunched(0, address(fee), arrived);
        (, address vault, address faucet) = _launchRaw(IERC20(address(fee)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);

        assertEq(fee.balanceOf(vault), arrived, "vault holds exactly what arrived");
        assertEq(fee.balanceOf(address(lp)), 0, "factory holds nothing (one transfer fee only)");
        assertEq(fee.balanceOf(launcher), 0);

        // Drip: the event shows the amount SENT; the faucet receives 1% less.
        vm.expectEmit(false, false, false, true, vault);
        emit IDripVault.Dripped(990e18, arrived - 990e18);
        assertEq(IDripVault(vault).drip(), 990e18);
        assertEq(fee.balanceOf(vault), 98_010e18);
        assertEq(fee.balanceOf(faucet), 980.1e18);

        // Claim: the event shows the amount SENT; alice receives 1% less.
        vm.expectEmit(true, false, false, true, faucet);
        emit IDripFaucet.Claimed(alice, CLAIM);
        vm.prank(alice);
        assertEq(IDripFaucet(faucet).claim(), CLAIM);
        assertEq(fee.balanceOf(alice), 9.9e18);
        assertEq(fee.balanceOf(faucet), 980.1e18 - CLAIM);
    }

    // --------------------------------------------------------------- case 11
    function test_Launchpad_RejectsZeroToken() public {
        vm.expectRevert(IDripLaunchpad.InvalidToken.selector);
        _launchRaw(IERC20(address(0)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
    }

    function test_Launchpad_RejectsZeroAmount() public {
        vm.expectRevert(IDripLaunchpad.InvalidAmount.selector);
        _launchRaw(IERC20(address(token)), 0, BPS, PERIOD, CLAIM, COOLDOWN);
    }

    function test_Launchpad_RejectsDripBpsZero() public {
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.InvalidDripBps.selector, uint16(0)));
        _launchRaw(IERC20(address(token)), AMOUNT, 0, PERIOD, CLAIM, COOLDOWN);
    }

    function test_Launchpad_RejectsDripBps10000() public {
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.InvalidDripBps.selector, uint16(10_000)));
        _launchRaw(IERC20(address(token)), AMOUNT, 10_000, PERIOD, CLAIM, COOLDOWN);
    }

    function test_Launchpad_RejectsDripBps65535() public {
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.InvalidDripBps.selector, type(uint16).max));
        _launchRaw(IERC20(address(token)), AMOUNT, type(uint16).max, PERIOD, CLAIM, COOLDOWN);
    }

    function test_Launchpad_RejectsPeriodBelowOneHour() public {
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.PeriodTooShort.selector, uint64(1 hours - 1)));
        _launchRaw(IERC20(address(token)), AMOUNT, BPS, 1 hours - 1, CLAIM, COOLDOWN);
    }

    function test_Launchpad_RejectsClaimAmountZero() public {
        vm.expectRevert(IDripLaunchpad.InvalidClaimAmount.selector);
        _launchRaw(IERC20(address(token)), AMOUNT, BPS, PERIOD, 0, COOLDOWN);
    }

    function test_Launchpad_RejectsCooldown59() public {
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.CooldownTooShort.selector, uint64(59)));
        _launchRaw(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, 59);
    }

    function test_Launchpad_RejectsTokenThatMovesNothing() public {
        NoOpTransferFromToken noop = new NoOpTransferFromToken();
        vm.expectRevert(IDripLaunchpad.NothingReceived.selector);
        _launchRaw(IERC20(address(noop)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
        assertEq(lp.launchCount(), 0, "a rejected launch leaves no trace");
    }

    function test_Launchpad_RejectedLaunchLeavesNoTrace() public {
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.InvalidDripBps.selector, uint16(0)));
        _launchRaw(IERC20(address(token)), AMOUNT, 0, PERIOD, CLAIM, COOLDOWN);
        assertEq(lp.launchCount(), 0);
        assertEq(token.balanceOf(launcher), 10 * AMOUNT);
    }

    function test_Launchpad_AcceptsDripBpsBoundaries() public {
        (, address v1,) = _launchRaw(IERC20(address(token)), AMOUNT, 1, PERIOD, CLAIM, COOLDOWN);
        (, address v2,) = _launchRaw(IERC20(address(token)), AMOUNT, 9999, PERIOD, CLAIM, COOLDOWN);
        assertEq(IDripVault(v1).dripBps(), 1);
        assertEq(IDripVault(v2).dripBps(), 9999);
        assertEq(IDripVault(v1).drip(), 10e18, "0.01% of 100,000");
        assertEq(IDripVault(v2).drip(), 99_990e18, "99.99% of 100,000");
        assertEq(token.balanceOf(v2), 10e18, "the vault is never emptied");
    }

    function test_Launchpad_AcceptsPeriodBoundaries() public {
        (, address v1,) = _launchRaw(IERC20(address(token)), AMOUNT, BPS, 1 hours, CLAIM, COOLDOWN);
        (, address v2,) = _launchRaw(IERC20(address(token)), AMOUNT, BPS, type(uint64).max, CLAIM, COOLDOWN);
        assertEq(IDripVault(v1).period(), 1 hours);
        assertEq(IDripVault(v2).period(), type(uint64).max);
        // The first drip is still immediate with the largest period.
        assertEq(IDripVault(v2).nextDripAt(), T0);
        assertEq(IDripVault(v2).drip(), 1_000e18);
        vm.warp(T0 + 100 * 365 days);
        vm.expectRevert(abi.encodeWithSelector(IDripVault.DripTooSoon.selector, T0 + uint256(type(uint64).max)));
        IDripVault(v2).drip();
    }

    function test_Launchpad_AcceptsCooldownBoundaries() public {
        (,, address f1) = _launchRaw(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, 60);
        (, address v2, address f2) = _launchRaw(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, type(uint64).max);
        assertEq(IDripFaucet(f1).cooldown(), 60);
        assertEq(IDripFaucet(f2).cooldown(), type(uint64).max);

        // "Claim once ever": a second claim is never possible.
        IDripVault(v2).drip();
        vm.prank(alice);
        assertEq(IDripFaucet(f2).claim(), CLAIM);
        vm.warp(T0 + 100 * 365 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDripFaucet.CooldownActive.selector, T0 + uint256(type(uint64).max)));
        IDripFaucet(f2).claim();
    }

    // --------------------------------------------------------------- case 12
    function test_Launchpad_Enumeration() public {
        assertEq(lp.launchCount(), 0);
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.UnknownLaunch.selector, uint256(0)));
        lp.launches(0);

        (uint256 id0, address v0, address f0) = _launch();
        (uint256 id1, address v1, address f1) = _launch();
        (uint256 id2, address v2, address f2) = _launch();
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(lp.launchCount(), 3);

        (address v, address f) = lp.launches(0);
        assertEq(v, v0);
        assertEq(f, f0);
        (v, f) = lp.launches(1);
        assertEq(v, v1);
        assertEq(f, f1);
        (v, f) = lp.launches(2);
        assertEq(v, v2);
        assertEq(f, f2);
        assertTrue(v0 != v1 && v1 != v2 && f0 != f1 && f1 != f2);

        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.UnknownLaunch.selector, uint256(3)));
        lp.launches(3);
        vm.expectRevert(abi.encodeWithSelector(IDripLaunchpad.UnknownLaunch.selector, type(uint256).max));
        lp.launches(type(uint256).max);
    }

    // ---------------------------------------------------- pulls from msg.sender only
    function test_Launchpad_NobodyCanSpendSomeoneElsesAllowance() public {
        // The launcher approved the factory in setUp and still holds the tokens.
        uint256 launcherBefore = token.balanceOf(launcher);
        vm.prank(random);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(lp), 0, AMOUNT)
        );
        lp.launch(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
        assertEq(token.balanceOf(launcher), launcherBefore, "launcher tokens untouched");
        assertEq(lp.launchCount(), 0);
    }

    function test_Launchpad_AnyoneCanLaunchWithOwnTokens() public {
        token.mint(random, AMOUNT);
        vm.startPrank(random);
        token.approve(address(lp), AMOUNT);
        (, address vault,) = lp.launch(IERC20(address(token)), AMOUNT, BPS, PERIOD, CLAIM, COOLDOWN);
        vm.stopPrank();
        assertEq(token.balanceOf(vault), AMOUNT);
        assertEq(token.balanceOf(random), 0);
        assertEq(token.balanceOf(launcher), 10 * AMOUNT, "launcher unaffected");
    }
}
