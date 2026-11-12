// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DripLaunchpad} from "contracts/DripLaunchpad.sol";
import {IDripVault} from "contracts/interfaces/IDripVault.sol";
import {IDripFaucet} from "contracts/interfaces/IDripFaucet.sol";
import {DripDemoToken} from "contracts/script/DripDemoToken.sol";

/// @notice Arc TESTNET demo: deploys a demo token and the launchpad, launches once, then calls drip()
/// and claim() once each. Not for mainnet: it refuses to run on any chain except Arc Testnet.
///
/// The deployer key is read ONLY from the environment variable DEPLOYER_PRIVATE_KEY (never pass it on the
/// command line). Run (when you decide to):
///   DEPLOYER_PRIVATE_KEY=... forge script contracts/script/DeployDemo.s.sol --rpc-url <arc testnet rpc> --broadcast
contract DeployDemo is Script {
    uint256 internal constant ARC_TESTNET_CHAIN_ID = 5042002;

    uint256 internal constant SUPPLY = 1_000_000e18;
    uint256 internal constant LAUNCH_AMOUNT = 100_000e18;
    uint16 internal constant DRIP_BPS = 100;
    uint64 internal constant PERIOD = 1 days;
    uint256 internal constant CLAIM_AMOUNT = 10e18;
    uint64 internal constant COOLDOWN = 8 hours;

    error WrongChain(uint256 chainId);

    function run() external {
        if (block.chainid != ARC_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        DripDemoToken token = new DripDemoToken(SUPPLY);
        DripLaunchpad launchpad = new DripLaunchpad();

        token.approve(address(launchpad), LAUNCH_AMOUNT);
        (uint256 id, address vault, address faucet) =
            launchpad.launch(IERC20(address(token)), LAUNCH_AMOUNT, DRIP_BPS, PERIOD, CLAIM_AMOUNT, COOLDOWN);

        uint256 dripped = IDripVault(vault).drip();
        uint256 claimed = IDripFaucet(faucet).claim();

        vm.stopBroadcast();

        console2.log("Chain id        :", block.chainid);
        console2.log("DripDemoToken   :", address(token));
        console2.log("DripLaunchpad   :", address(launchpad));
        console2.log("Launch id       :", id);
        console2.log("DripVault       :", vault);
        console2.log("DripFaucet      :", faucet);
        console2.log("First drip      :", dripped);
        console2.log("First claim     :", claimed);
    }
}
