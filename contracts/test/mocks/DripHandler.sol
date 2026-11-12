// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";
import {MockERC20} from "contracts/test/mocks/MockERC20.sol";

/// @dev Invariant-test handler. Actors: launcher, factory deployer, random addresses. Actions: drip,
/// claim, warp, donate to the vault or faucet, launch another, junk calls. Every effect is measured
/// from token balances (never from the contracts' own return values) and kept in ghost state.
contract DripHandler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Params {
        address vault;
        address faucet;
        uint16 dripBps;
        uint64 period;
        uint256 claimAmount;
        uint64 cooldown;
    }

    IDripLaunchpad public immutable lp;
    MockERC20 public immutable token;
    address[] public actors; // launcher, deployer, randoms
    Params[] public params;

    // ghost state
    uint256 public ghostReceived; // tokens that arrived in vaults through launch()
    uint256 public ghostDonated;
    uint256 public ghostClaimed; // sum of measured balance deltas of claimers
    uint256 public successfulDrips;
    uint256 public successfulClaims;
    uint256 public okCalls; // junk calls that succeeded (views only)
    bool public cooldownViolation;
    bool public periodViolation;
    bool public returnValueMismatch;
    mapping(address => uint256) public ghostDrippedTo; // faucet => tokens that left the vault into it
    mapping(address => uint256) public ghostDonatedTo; // vault or faucet => donations
    mapping(address => uint256) public ghostPaidBy; // faucet => tokens it paid out
    mapping(address => uint256) public lastDripAt; // vault => timestamp of last successful drip
    mapping(address => mapping(address => uint256)) public lastPaidAt; // faucet => who => timestamp

    constructor(IDripLaunchpad lp_, MockERC20 token_, address[] memory actors_) {
        lp = lp_;
        token = token_;
        actors = actors_;
        _launch(1_000_000e18, 100, 1 days, 10e18, 8 hours, actors_[0]);
    }

    // ------------------------------------------------------------ views
    function launchCountTracked() external view returns (uint256) {
        return params.length;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ---------------------------------------------------------- actions
    function drip(uint256 li, uint256 actorSeed) external {
        Params memory p = params[li % params.length];
        address actor = actors[actorSeed % actors.length];
        uint256 vaultBefore = token.balanceOf(p.vault);
        uint256 faucetBefore = token.balanceOf(p.faucet);

        vm.prank(actor);
        try IDripVault(p.vault).drip() returns (uint256 amount) {
            if (lastDripAt[p.vault] != 0 && block.timestamp < lastDripAt[p.vault] + p.period) periodViolation = true;
            lastDripAt[p.vault] = block.timestamp;
            successfulDrips += 1;
            uint256 vaultDelta = vaultBefore - token.balanceOf(p.vault);
            uint256 faucetDelta = token.balanceOf(p.faucet) - faucetBefore;
            if (vaultDelta != amount || faucetDelta != amount) returnValueMismatch = true;
            ghostDrippedTo[p.faucet] += faucetDelta;
        } catch {}
    }

    function claim(uint256 li, uint256 actorSeed) external {
        Params memory p = params[li % params.length];
        address actor = actors[actorSeed % actors.length];
        uint256 actorBefore = token.balanceOf(actor);
        uint256 faucetBefore = token.balanceOf(p.faucet);

        vm.prank(actor);
        try IDripFaucet(p.faucet).claim() returns (uint256 amount) {
            uint256 prev = lastPaidAt[p.faucet][actor];
            if (prev != 0 && block.timestamp < prev + p.cooldown) cooldownViolation = true;
            lastPaidAt[p.faucet][actor] = block.timestamp;
            successfulClaims += 1;
            uint256 delta = token.balanceOf(actor) - actorBefore;
            if (delta != amount || faucetBefore - token.balanceOf(p.faucet) != amount) returnValueMismatch = true;
            ghostClaimed += delta;
            ghostPaidBy[p.faucet] += delta;
        } catch {}
    }

    function warp(uint256 dt) external {
        // mostly small steps, sometimes big jumps
        uint256 step = dt % 10 == 0 ? (dt % (60 days)) : (dt % (2 days));
        vm.warp(block.timestamp + step);
    }

    function donate(uint256 li, bool toVault, uint256 amount) external {
        Params memory p = params[li % params.length];
        amount = (amount % 1e24) + 1;
        address to = toVault ? p.vault : p.faucet;
        token.mint(address(this), amount);
        token.transfer(to, amount);
        ghostDonated += amount;
        ghostDonatedTo[to] += amount;
    }

    function launchAnother(uint256 amount, uint256 bps, uint256 period, uint256 claimAmount, uint256 cooldown)
        external
    {
        if (params.length >= 6) return;
        _launch(
            (amount % 1e30) + 1,
            uint16((bps % 9999) + 1),
            uint64(1 hours + (period % 30 days)),
            (claimAmount % 1e24) + 1,
            uint64(1 minutes + (cooldown % 30 days)),
            actors[((amount % 1000) + (bps % 1000)) % actors.length]
        );
    }

    /// Random calls with random selectors. drip/claim/launch selectors are skipped so the ghost
    /// accounting stays exact; everything else must be unable to change anything.
    function junk(uint256 li, uint256 actorSeed, bytes4 sel, bytes calldata data, uint256 value) external {
        if (
            sel == IDripVault.drip.selector || sel == IDripFaucet.claim.selector
                || sel == IDripLaunchpad.launch.selector
        ) return;
        Params memory p = params[li % params.length];
        address actor = actors[actorSeed % actors.length];
        address[3] memory targets = [address(lp), p.vault, p.faucet];
        address target = targets[uint256(keccak256(abi.encode(li, actorSeed))) % 3];
        uint256 v = value % 3 == 0 ? (value % 1 ether) : 0;
        vm.deal(actor, v);
        vm.prank(actor);
        // Only view functions can possibly succeed; they cannot change state.
        (bool ok,) = target.call{value: v}(abi.encodePacked(sel, data));
        if (ok) okCalls += 1;
    }

    // --------------------------------------------------------- internal
    function _launch(uint256 amount, uint16 bps, uint64 period, uint256 claimAmount, uint64 cooldown, address who)
        private
    {
        token.mint(who, amount);
        vm.startPrank(who);
        token.approve(address(lp), amount);
        uint256 balBefore;
        (address v, address f) = _peekNext();
        balBefore = token.balanceOf(v);
        (, address vault, address faucet) = lp.launch(IERC20(address(token)), amount, bps, period, claimAmount, cooldown);
        vm.stopPrank();
        require(vault == v && faucet == f, "unexpected addresses");
        ghostReceived += token.balanceOf(vault) - balBefore;
        params.push(Params(vault, faucet, bps, period, claimAmount, cooldown));
    }

    function _peekNext() private view returns (address v, address f) {
        uint64 n = vm.getNonce(address(lp));
        f = vm.computeCreateAddress(address(lp), n);
        v = vm.computeCreateAddress(address(lp), n + 1);
    }
}
