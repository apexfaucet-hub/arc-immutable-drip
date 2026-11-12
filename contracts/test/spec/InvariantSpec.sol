// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {SpecBase} from "contracts/test/spec/SpecBase.sol";
import {DripHandler} from "contracts/test/mocks/DripHandler.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Case 13: invariant suite over a standard token.
abstract contract InvariantSpec is SpecBase {
    MockERC20 internal token;
    DripHandler internal handler;

    function setUp() public virtual {
        _initTime();
        vm.prank(deployer);
        address lp = address(_newLaunchpad());
        token = new MockERC20();

        address[] memory actors = new address[](5);
        actors[0] = launcher;
        actors[1] = deployer;
        actors[2] = random;
        actors[3] = alice;
        actors[4] = bob;
        handler = new DripHandler(IDripLaunchpad(lp), token, actors);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = DripHandler.drip.selector;
        selectors[1] = DripHandler.claim.selector;
        selectors[2] = DripHandler.warp.selector;
        selectors[3] = DripHandler.donate.selector;
        selectors[4] = DripHandler.launchAnother.selector;
        selectors[5] = DripHandler.junk.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// vault + faucet + all claimers == received + donations (every launch together).
    function invariant_TokenConservation() public view {
        uint256 held;
        uint256 n = handler.launchCountTracked();
        for (uint256 i = 0; i < n; i++) {
            (address v, address f,,,,) = handler.params(i);
            held += token.balanceOf(v) + token.balanceOf(f);
        }
        assertEq(held + handler.ghostClaimed(), handler.ghostReceived() + handler.ghostDonated(), "conservation");
    }

    function invariant_VaultBalanceNeverZero() public view {
        uint256 n = handler.launchCountTracked();
        for (uint256 i = 0; i < n; i++) {
            (address v,,,,,) = handler.params(i);
            assertGt(token.balanceOf(v), 0, "vault ran dry");
        }
    }

    /// total paid by a faucet <= total dripped into it + donations to it
    function invariant_FaucetPaysOutNoMoreThanItReceived() public view {
        uint256 n = handler.launchCountTracked();
        for (uint256 i = 0; i < n; i++) {
            (, address f,,,,) = handler.params(i);
            assertLe(handler.ghostPaidBy(f), handler.ghostDrippedTo(f) + handler.ghostDonatedTo(f));
        }
    }

    function invariant_NoAddressPaidTwiceWithinOneCooldown() public view {
        assertFalse(handler.cooldownViolation());
    }

    function invariant_NoTwoDripsCloserThanOnePeriod() public view {
        assertFalse(handler.periodViolation());
    }

    function invariant_ReturnValuesMatchMeasuredBalances() public view {
        assertFalse(handler.returnValueMismatch());
    }

    function invariant_ImmutablesNeverChange() public view {
        uint256 n = handler.launchCountTracked();
        for (uint256 i = 0; i < n; i++) {
            (address v, address f, uint16 bps, uint64 period, uint256 claimAmount, uint64 cooldown) = handler.params(i);
            assertEq(IDripVault(v).dripBps(), bps);
            assertEq(IDripVault(v).period(), period);
            assertEq(IDripVault(v).faucet(), f);
            assertEq(address(IDripVault(v).token()), address(token));
            assertEq(IDripFaucet(f).claimAmount(), claimAmount);
            assertEq(IDripFaucet(f).cooldown(), cooldown);
            assertEq(address(IDripFaucet(f).token()), address(token));
        }
    }
}
