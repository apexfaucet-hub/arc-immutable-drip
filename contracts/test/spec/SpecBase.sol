// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripLaunchpad} from "contracts/interfaces/IDripLaunchpad.sol";

/// @dev Shared base of every spec contract. The spec contracts hold the test functions; a concrete
/// contract only chooses WHICH implementation sits behind the three hooks. The default profile plugs
/// in the production contracts (`RealHooks`); the `planted` profile plugs in deliberately faulty copies.
abstract contract SpecBase is Test {
    uint256 internal constant T0 = 1_750_000_000;

    address internal launcher = makeAddr("launcher");
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal random = makeAddr("random");

    /// @dev Called first by every spec's setUp. Foundry's default timestamp is 1, which would make
    /// every time check vacuous.
    function _initTime() internal {
        vm.warp(T0);
    }

    function _newFaucet(IERC20 token, uint256 claimAmount, uint64 cooldown) internal virtual returns (IDripFaucet);

    function _newVault(IERC20 token, address faucet, uint16 dripBps, uint64 period)
        internal
        virtual
        returns (IDripVault);

    function _newLaunchpad() internal virtual returns (IDripLaunchpad);
}
