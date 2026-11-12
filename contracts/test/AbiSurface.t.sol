// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// @dev Case 8 (a): the external function set of each production contract equals EXACTLY the expected
/// list. Reads `methodIdentifiers` from the compiled artifacts (fs_permissions: read-only on the out
/// directory, nothing else).
contract AbiSurfaceTest is Test {
    function _surface(string memory name) internal view returns (string[] memory) {
        string memory path = string.concat(vm.projectRoot(), "/contracts/out/", name, ".sol/", name, ".json");
        string memory json = vm.readFile(path);
        return vm.parseJsonKeys(json, ".methodIdentifiers");
    }

    function _assertExactly(string memory name, string[] memory expected) internal view {
        string[] memory actual = _surface(name);
        assertEq(actual.length, expected.length, string.concat(name, ": function count"));
        for (uint256 i = 0; i < expected.length; i++) {
            bool found;
            for (uint256 j = 0; j < actual.length; j++) {
                if (keccak256(bytes(actual[j])) == keccak256(bytes(expected[i]))) found = true;
            }
            assertTrue(found, string.concat(name, ": missing ", expected[i]));
        }
    }

    function test_Abi_DripFaucetSurface() public view {
        string[] memory e = new string[](6);
        e[0] = "claim()";
        e[1] = "claimAmount()";
        e[2] = "cooldown()";
        e[3] = "lastClaim(address)";
        e[4] = "nextClaimAt(address)";
        e[5] = "token()";
        _assertExactly("DripFaucet", e);
    }

    function test_Abi_DripVaultSurface() public view {
        string[] memory e = new string[](6);
        e[0] = "drip()";
        e[1] = "dripBps()";
        e[2] = "faucet()";
        e[3] = "nextDripAt()";
        e[4] = "period()";
        e[5] = "token()";
        _assertExactly("DripVault", e);
    }

    function test_Abi_DripLaunchpadSurface() public view {
        string[] memory e = new string[](3);
        e[0] = "launch(address,uint256,uint16,uint64,uint256,uint64)";
        e[1] = "launchCount()";
        e[2] = "launches(uint256)";
        _assertExactly("DripLaunchpad", e);
    }

    /// Only drip, claim and launch can change state: every other listed function is a view/getter.
    function test_Abi_OnlyThreeStateChangingFunctions() public view {
        string[3] memory names = ["DripFaucet", "DripVault", "DripLaunchpad"];
        uint256 mutating;
        for (uint256 n = 0; n < names.length; n++) {
            string memory path =
                string.concat(vm.projectRoot(), "/contracts/out/", names[n], ".sol/", names[n], ".json");
            string memory json = vm.readFile(path);
            // abi[i].stateMutability
            for (uint256 i = 0; i < 64; i++) {
                string memory key = string.concat(".abi[", vm.toString(i), "]");
                if (!vm.keyExistsJson(json, key)) break;
                string memory kind = vm.parseJsonString(json, string.concat(key, ".type"));
                if (keccak256(bytes(kind)) != keccak256("function")) continue;
                string memory sm = vm.parseJsonString(json, string.concat(key, ".stateMutability"));
                assertFalse(keccak256(bytes(sm)) == keccak256("payable"), "no payable function");
                if (keccak256(bytes(sm)) == keccak256("nonpayable")) {
                    mutating++;
                    string memory fn = vm.parseJsonString(json, string.concat(key, ".name"));
                    bool allowed = keccak256(bytes(fn)) == keccak256("claim") || keccak256(bytes(fn)) == keccak256("drip")
                        || keccak256(bytes(fn)) == keccak256("launch");
                    assertTrue(allowed, string.concat("unexpected state-changing function: ", fn));
                }
            }
        }
        assertEq(mutating, 3);
    }

    function test_Abi_NoReceiveOrFallback() public view {
        string[3] memory names = ["DripFaucet", "DripVault", "DripLaunchpad"];
        for (uint256 n = 0; n < names.length; n++) {
            string memory path =
                string.concat(vm.projectRoot(), "/contracts/out/", names[n], ".sol/", names[n], ".json");
            string memory json = vm.readFile(path);
            for (uint256 i = 0; i < 64; i++) {
                string memory key = string.concat(".abi[", vm.toString(i), "]");
                if (!vm.keyExistsJson(json, key)) break;
                string memory kind = vm.parseJsonString(json, string.concat(key, ".type"));
                assertTrue(keccak256(bytes(kind)) != keccak256("receive"), "no receive");
                assertTrue(keccak256(bytes(kind)) != keccak256("fallback"), "no fallback");
            }
        }
    }
}
