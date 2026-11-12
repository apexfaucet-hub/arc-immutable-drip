// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// @dev The external function set of Split and SplitFactory equals EXACTLY the expected list, only
/// release, withdraw and createSplit change state, and nothing is payable. Reads the compiled artifacts
/// (fs_permissions: read-only on the out directory).
contract SplitAbiSurfaceTest is Test {
    function _json(string memory name) internal view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/contracts/out/", name, ".sol/", name, ".json"));
    }

    function _assertExactly(string memory name, string[] memory expected) internal view {
        string[] memory actual = vm.parseJsonKeys(_json(name), ".methodIdentifiers");
        assertEq(actual.length, expected.length, string.concat(name, ": function count"));
        for (uint256 i = 0; i < expected.length; i++) {
            bool found;
            for (uint256 j = 0; j < actual.length; j++) {
                if (keccak256(bytes(actual[j])) == keccak256(bytes(expected[i]))) found = true;
            }
            assertTrue(found, string.concat(name, ": missing ", expected[i]));
        }
    }

    function test_SplitAbi_SplitSurface() public view {
        string[] memory e = new string[](8);
        e[0] = "payee0()";
        e[1] = "payee1()";
        e[2] = "shares0()";
        e[3] = "shares1()";
        e[4] = "ledger(address)";
        e[5] = "pending(address,address)";
        e[6] = "release(address)";
        e[7] = "withdraw(address)";
        _assertExactly("Split", e);
    }

    function test_SplitAbi_SplitFactorySurface() public view {
        string[] memory e = new string[](4);
        e[0] = "createSplit(address[2],uint16[2])";
        e[1] = "isSplit(address)";
        e[2] = "splitCount()";
        e[3] = "splits(uint256)";
        _assertExactly("SplitFactory", e);
    }

    function test_SplitAbi_OnlyReleaseWithdrawAndCreateSplitChangeState() public view {
        string[2] memory names = ["Split", "SplitFactory"];
        uint256 mutating;
        for (uint256 n = 0; n < names.length; n++) {
            string memory json = _json(names[n]);
            for (uint256 i = 0; i < 64; i++) {
                string memory key = string.concat(".abi[", vm.toString(i), "]");
                if (!vm.keyExistsJson(json, key)) break;
                string memory kind = vm.parseJsonString(json, string.concat(key, ".type"));
                assertTrue(keccak256(bytes(kind)) != keccak256("receive"), "no receive");
                assertTrue(keccak256(bytes(kind)) != keccak256("fallback"), "no fallback");
                if (keccak256(bytes(kind)) != keccak256("function")) continue;
                string memory sm = vm.parseJsonString(json, string.concat(key, ".stateMutability"));
                assertFalse(keccak256(bytes(sm)) == keccak256("payable"), "no payable function");
                if (keccak256(bytes(sm)) == keccak256("nonpayable")) {
                    mutating++;
                    string memory fn = vm.parseJsonString(json, string.concat(key, ".name"));
                    bool allowed = keccak256(bytes(fn)) == keccak256("release")
                        || keccak256(bytes(fn)) == keccak256("withdraw")
                        || keccak256(bytes(fn)) == keccak256("createSplit");
                    assertTrue(allowed, string.concat("unexpected state-changing function: ", fn));
                }
            }
        }
        assertEq(mutating, 3);
    }
}
