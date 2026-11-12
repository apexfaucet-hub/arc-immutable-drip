// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {SplitFactory} from "contracts/SplitFactory.sol";

/// @notice Arc TESTNET only: deploys the SplitFactory and, if SPLIT_PAYEE0 and SPLIT_PAYEE1 are set in the
/// environment, creates one 70/30 split for them. It refuses to run on any chain except Arc Testnet.
///
/// The deployer key is read ONLY from the environment variable DEPLOYER_PRIVATE_KEY (never pass it on the
/// command line). Run (when you decide to):
///   DEPLOYER_PRIVATE_KEY=... forge script contracts/script/DeploySplit.s.sol --rpc-url <arc testnet rpc> --broadcast
contract DeploySplit is Script {
    uint256 internal constant ARC_TESTNET_CHAIN_ID = 5042002;

    error WrongChain(uint256 chainId);

    function run() external {
        if (block.chainid != ARC_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        SplitFactory factory = new SplitFactory();
        console2.log("Chain id     :", block.chainid);
        console2.log("SplitFactory :", address(factory));

        address payee0 = vm.envOr("SPLIT_PAYEE0", address(0));
        address payee1 = vm.envOr("SPLIT_PAYEE1", address(0));
        if (payee0 != address(0) && payee1 != address(0)) {
            address split = factory.createSplit([payee0, payee1], [uint16(7000), uint16(3000)]);
            console2.log("Demo split   :", split);
        }

        vm.stopBroadcast();
    }
}
