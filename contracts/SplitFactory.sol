// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Split} from "contracts/Split.sol";
import {ISplitFactory} from "contracts/interfaces/ISplitFactory.sol";

/// @notice Permissionless factory for immutable two-payee splits. No owner, no fee, no constructor
/// arguments, no immutables. It never holds tokens and has no payable function.
contract SplitFactory is ISplitFactory {
    address[] private _splits;

    /// @inheritdoc ISplitFactory
    mapping(address => bool) public isSplit;

    /// @inheritdoc ISplitFactory
    function splitCount() external view returns (uint256) {
        return _splits.length;
    }

    /// @inheritdoc ISplitFactory
    function splits(uint256 id) external view returns (address) {
        if (id >= _splits.length) revert UnknownSplit(id);
        return _splits[id];
    }

    /// @inheritdoc ISplitFactory
    /// @dev All validation (non-zero distinct payees, non-zero shares summing to exactly 10000) happens in
    /// the Split constructor, so a split deployed directly is exactly as safe; its custom error bubbles up.
    function createSplit(address[2] calldata payees, uint16[2] calldata sharesBps) external returns (address split) {
        split = address(new Split(payees, sharesBps));
        _splits.push(split);
        isSplit[split] = true;
        emit SplitCreated(split, payees, sharesBps, msg.sender);
    }
}
