// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {SplitSpecBase} from "contracts/test/spec/SplitSpecBase.sol";
import {SplitHandler} from "contracts/test/mocks/SplitHandler.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Stateful invariants of a 70/30 split over a standard token.
abstract contract SplitInvariantSpec is SplitSpecBase {
    MockERC20 internal token;
    IERC20 internal t;
    ISplit internal split;
    SplitHandler internal handler;

    function setUp() public virtual {
        _initTime();
        token = new MockERC20();
        t = IERC20(address(token));
        split = _newSplit(_pair(alice, bob), _bps(7000, 3000));

        address[] memory callers = new address[](4);
        callers[0] = alice;
        callers[1] = bob;
        callers[2] = carol;
        callers[3] = random;
        handler = new SplitHandler(split, token, callers);
        targetContract(address(handler));
    }

    /// Tokens in + tokens out == tokens held; nobody is ever paid more than was received.
    function invariant_Split_Conservation() public view {
        assertEq(
            token.balanceOf(address(split)) + handler.ghostWithdrawn0() + handler.ghostWithdrawn1(),
            handler.ghostReceived()
        );
    }

    function invariant_Split_PendingNeverExceedsBalance() public view {
        (,,, uint256 p0, uint256 p1) = split.ledger(t);
        assertLe(p0 + p1, token.balanceOf(address(split)));
    }

    /// Credits are always the exact floor of the cumulative accounted inflow, so each payee is within
    /// one unit of its share and the rounding dust is at most one unit.
    function invariant_Split_CreditsAreExactFloorsOfAccountedInflow() public view {
        (uint256 accounted, uint256 a0, uint256 a1,,) = split.ledger(t);
        assertLe(accounted, handler.ghostReceived());
        assertEq(a0, accounted * 7000 / 10_000);
        assertEq(a1, accounted * 3000 / 10_000);
        assertLe(accounted - a0 - a1, 1);
    }

    function invariant_Split_WithdrawalsNeverExceedCredit() public view {
        (,uint256 a0, uint256 a1,,) = split.ledger(t);
        assertLe(handler.ghostWithdrawn0(), a0);
        assertLe(handler.ghostWithdrawn1(), a1);
    }

    function invariant_Split_AccountingIsMonotonicAndStrangersGetNothing() public view {
        assertFalse(handler.accountedWentDown());
        assertFalse(handler.strangerWithdrew());
        assertFalse(handler.overpaid());
    }

    function invariant_Split_ConfigurationNeverChanges() public view {
        assertEq(split.payee0(), alice);
        assertEq(split.payee1(), bob);
        assertEq(split.shares0(), 7000);
        assertEq(split.shares1(), 3000);
    }
}
