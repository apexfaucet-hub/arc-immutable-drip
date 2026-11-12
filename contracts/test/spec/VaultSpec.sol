// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Behaviour of a DripVault. Runs against whatever `_newVault` returns.
abstract contract VaultSpec is SpecBase {
    uint256 internal constant FUNDED = 1_000_000e18;
    uint16 internal constant BPS = 100; // 1%
    uint64 internal constant PERIOD = 1 days;

    MockERC20 internal token;
    address internal faucetAddr;
    IDripVault internal vault;

    function setUp() public virtual {
        _initTime();
        token = new MockERC20();
        faucetAddr = makeAddr("faucet");
        vault = _newVault(IERC20(address(token)), faucetAddr, BPS, PERIOD);
        token.mint(address(vault), FUNDED);
    }

    function test_Vault_Immutables() public view {
        assertEq(address(vault.token()), address(token));
        assertEq(vault.faucet(), faucetAddr);
        assertEq(vault.dripBps(), BPS);
        assertEq(vault.period(), PERIOD);
    }

    /// The first drip is available immediately at deployment.
    function test_Vault_FirstDripIsAvailableImmediately() public {
        assertEq(vault.nextDripAt(), T0, "nextDripAt starts at the deployment timestamp");
        vm.prank(alice);
        uint256 amount = vault.drip();
        assertEq(amount, 10_000e18, "1% of 1,000,000");
        assertEq(token.balanceOf(faucetAddr), 10_000e18);
        assertEq(token.balanceOf(address(vault)), FUNDED - 10_000e18);
        assertEq(vault.nextDripAt(), T0 + PERIOD);
    }

    /// Case 2.
    function test_Vault_DripTwiceInOnePeriodReverts() public {
        assertEq(vault.drip(), 10_000e18, "first drip pays exactly 1%");
        uint256 next = vault.nextDripAt();
        assertEq(next, T0 + PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IDripVault.DripTooSoon.selector, next));
        vault.drip();
        assertEq(token.balanceOf(faucetAddr), 10_000e18, "nothing extra paid");

        vm.warp(next - 1);
        vm.expectRevert(abi.encodeWithSelector(IDripVault.DripTooSoon.selector, next));
        vault.drip();

        vm.warp(next);
        assertEq(vault.drip(), 9_900e18, "1% of 990,000 at exactly nextDripAt");
        assertEq(vault.nextDripAt(), next + PERIOD);
    }

    /// Case 3: missed periods do NOT accumulate.
    function test_Vault_MissedPeriodsDoNotAccumulate() public {
        assertEq(vault.drip(), 10_000e18, "first drip pays exactly 1%");

        vm.warp(block.timestamp + 10 * PERIOD);
        uint256 bal = token.balanceOf(address(vault));
        uint256 expected = Math.mulDiv(bal, BPS, 10_000);
        assertEq(expected, 9_900e18);
        uint256 faucetBefore = token.balanceOf(faucetAddr);
        assertEq(vault.drip(), expected, "exactly one period's worth");
        assertEq(token.balanceOf(faucetAddr), faucetBefore + expected);
        assertEq(token.balanceOf(address(vault)), bal - expected);

        uint256 dripTime = block.timestamp;
        assertEq(vault.nextDripAt(), dripTime + PERIOD, "clock restarts at block.timestamp");

        vm.expectRevert(abi.encodeWithSelector(IDripVault.DripTooSoon.selector, dripTime + PERIOD));
        vault.drip();

        vm.warp(dripTime + PERIOD - 1);
        vm.expectRevert(abi.encodeWithSelector(IDripVault.DripTooSoon.selector, dripTime + PERIOD));
        vault.drip();

        vm.warp(dripTime + PERIOD);
        uint256 balNow = token.balanceOf(address(vault));
        assertEq(balNow, 980_100e18);
        assertEq(vault.drip(), Math.mulDiv(balNow, BPS, 10_000));
    }

    /// Case 4: drip math over 1,000 consecutive drips.
    function testFuzz_Vault_DripMathOver1000Drips(uint16 bpsSeed, uint256 amountSeed) public {
        uint16 bps = uint16(bound(bpsSeed, 1, 9999));
        uint256 amount = bound(amountSeed, 1, 1e36);
        MockERC20 t = new MockERC20();
        IDripVault v = _newVault(IERC20(address(t)), faucetAddr, bps, 1 hours);
        t.mint(address(v), amount);

        for (uint256 i = 0; i < 1000; i++) {
            vm.warp(block.timestamp + 1 hours);
            uint256 balBefore = t.balanceOf(address(v));
            uint256 faucetBefore = t.balanceOf(faucetAddr);
            uint256 expected = Math.mulDiv(balBefore, bps, 10_000);
            assertGt(balBefore, 0, "vault balance is never zero");

            if (expected == 0) {
                uint256 next = v.nextDripAt();
                vm.expectRevert(IDripVault.NothingToDrip.selector);
                v.drip();
                assertEq(v.nextDripAt(), next, "state unchanged on dust");
                assertEq(t.balanceOf(address(v)), balBefore, "balance unchanged on dust");
                assertEq(t.balanceOf(faucetAddr), faucetBefore, "faucet unchanged on dust");
                break;
            }

            uint256 got = v.drip();
            assertEq(got, expected, "amount == mulDiv(bal, bps, 10000)");
            assertLt(got, balBefore, "a drip never takes the whole balance");
            assertEq(t.balanceOf(address(v)), balBefore - got, "remaining == before - amount");
            assertGt(t.balanceOf(address(v)), 0, "vault balance is never zero");
            assertEq(t.balanceOf(faucetAddr), faucetBefore + got, "faucet received exactly the drip");
            assertEq(v.nextDripAt(), block.timestamp + 1 hours);
        }
    }

    /// Case 4 (pure): over the FULL uint256 balance range mulDiv never reverts and is below the balance.
    function testFuzz_Vault_MulDivNeverRevertsAndIsBelowBalance(uint256 bal, uint16 bpsSeed) public pure {
        uint16 bps = uint16(bound(bpsSeed, 1, 9999));
        bal = bound(bal, 1, type(uint256).max);
        uint256 amount = Math.mulDiv(bal, bps, 10_000);
        assertLt(amount, bal);
        assertGt(bal - amount, 0);
    }

    function test_Vault_DustRevertsWithNothingToDrip() public {
        MockERC20 t = new MockERC20();
        IDripVault v = _newVault(IERC20(address(t)), faucetAddr, BPS, PERIOD);
        t.mint(address(v), 99); // mulDiv(99, 100, 10000) == 0
        uint256 next = v.nextDripAt();

        vm.recordLogs();
        vm.expectRevert(IDripVault.NothingToDrip.selector);
        v.drip();
        assertEq(v.nextDripAt(), next, "clock not restarted");
        assertEq(t.balanceOf(address(v)), 99);
        assertEq(t.balanceOf(faucetAddr), 0);
        assertEq(vm.getRecordedLogs().length, 0, "no event");

        // Empty vault: same thing.
        IDripVault e = _newVault(IERC20(address(t)), faucetAddr, BPS, PERIOD);
        vm.expectRevert(IDripVault.NothingToDrip.selector);
        e.drip();
    }

    function test_Vault_DrippedEvent() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit IDripVault.Dripped(10_000e18, FUNDED - 10_000e18);
        vault.drip();
    }

    function test_Vault_DrippedEventExactTopicsAndData() public {
        vm.recordLogs();
        vault.drip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2); // token Transfer + Dripped
        Vm.Log memory l = logs[1];
        assertEq(l.emitter, address(vault));
        assertEq(l.topics.length, 1);
        assertEq(l.topics[0], IDripVault.Dripped.selector);
        (uint256 amount, uint256 remaining) = abi.decode(l.data, (uint256, uint256));
        assertEq(amount, 10_000e18);
        assertEq(remaining, FUNDED - 10_000e18);
    }

    /// A period of type(uint64).max: the first drip is still immediate, a second never happens.
    function test_Vault_MaxPeriodFirstDripImmediateSecondNever() public {
        IDripVault v = _newVault(IERC20(address(token)), faucetAddr, BPS, type(uint64).max);
        token.mint(address(v), 1_000e18);
        assertEq(v.drip(), 10e18);
        uint256 next = T0 + uint256(type(uint64).max);
        assertEq(v.nextDripAt(), next);
        vm.warp(T0 + 100 * 365 days);
        vm.expectRevert(abi.encodeWithSelector(IDripVault.DripTooSoon.selector, next));
        v.drip();
    }

    function test_Vault_ConstructorRejectsBadParameters() public {
        IERC20 t = IERC20(address(token));
        vm.expectRevert(IDripVault.InvalidToken.selector);
        _newVault(IERC20(address(0)), faucetAddr, BPS, PERIOD);

        vm.expectRevert(IDripVault.InvalidFaucet.selector);
        _newVault(t, address(0), BPS, PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IDripVault.InvalidDripBps.selector, uint16(0)));
        _newVault(t, faucetAddr, 0, PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IDripVault.InvalidDripBps.selector, uint16(10_000)));
        _newVault(t, faucetAddr, 10_000, PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IDripVault.InvalidDripBps.selector, type(uint16).max));
        _newVault(t, faucetAddr, type(uint16).max, PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IDripVault.PeriodTooShort.selector, uint64(1 hours - 1)));
        _newVault(t, faucetAddr, BPS, 1 hours - 1);
    }

    function test_Vault_ConstructorAcceptsBoundaries() public {
        IERC20 t = IERC20(address(token));
        assertEq(_newVault(t, faucetAddr, 1, 1 hours).dripBps(), 1);
        assertEq(_newVault(t, faucetAddr, 9999, 1 hours).dripBps(), 9999);
        assertEq(_newVault(t, faucetAddr, BPS, 1 hours).period(), 1 hours);
        assertEq(_newVault(t, faucetAddr, BPS, type(uint64).max).period(), type(uint64).max);
    }
}
