// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISplit} from "contracts/interfaces/ISplit.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Invariant-test handler for a Split: fund, release (any caller), withdraw (payees and strangers),
/// junk calls. Every effect is measured from token balances and kept in ghost state.
contract SplitHandler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ISplit public immutable split;
    MockERC20 public immutable token;
    address public immutable payee0;
    address public immutable payee1;
    address[] public callers; // payee0, payee1, strangers

    uint256 public ghostReceived;
    uint256 public ghostWithdrawn0;
    uint256 public ghostWithdrawn1;
    uint256 public lastAccounted;
    uint256 public successfulWithdraws;
    uint256 public okJunk;
    bool public accountedWentDown;
    bool public strangerWithdrew;
    bool public overpaid;

    constructor(ISplit split_, MockERC20 token_, address[] memory callers_) {
        split = split_;
        token = token_;
        payee0 = split_.payee0();
        payee1 = split_.payee1();
        callers = callers_;
    }

    function fund(uint256 amount) external {
        amount = amount % 1e27; // anything from 0 to 1e27, many odd values
        if (amount == 0) return;
        token.mint(address(split), amount);
        ghostReceived += amount;
    }

    function fundTiny(uint256 amount) external {
        amount = (amount % 7) + 1; // 1..7 wei, the dust-heavy regime
        token.mint(address(split), amount);
        ghostReceived += amount;
    }

    function release(uint256 callerSeed) external {
        address caller = callers[callerSeed % callers.length];
        vm.prank(caller);
        try split.release(IERC20(address(token))) {} catch {}
        _track();
    }

    function withdraw(uint256 callerSeed) external {
        address who = callers[callerSeed % callers.length];
        uint256 before = token.balanceOf(who);
        vm.prank(who);
        try split.withdraw(IERC20(address(token))) returns (uint256 amount) {
            uint256 got = token.balanceOf(who) - before;
            if (got != amount) overpaid = true;
            successfulWithdraws += 1;
            if (who == payee0) ghostWithdrawn0 += got;
            else if (who == payee1) ghostWithdrawn1 += got;
            else strangerWithdrew = true;
        } catch {}
        _track();
    }

    /// Random calls with random selectors from random callers (except release/withdraw, which are
    /// handled above so the ghost accounting stays exact). None of them can succeed in changing anything.
    function junk(uint256 callerSeed, bytes4 sel, bytes calldata data, uint256 value) external {
        if (sel == ISplit.release.selector || sel == ISplit.withdraw.selector) return;
        address caller = callers[callerSeed % callers.length];
        uint256 v = value % 3 == 0 ? value % 1 ether : 0;
        vm.deal(caller, v);
        vm.prank(caller);
        (bool ok,) = address(split).call{value: v}(abi.encodePacked(sel, data));
        if (ok) okJunk += 1; // only view functions can succeed
    }

    function _track() private {
        (uint256 accounted,,,,) = split.ledger(IERC20(address(token)));
        if (accounted < lastAccounted) accountedWentDown = true;
        lastAccounted = accounted;
    }
}
