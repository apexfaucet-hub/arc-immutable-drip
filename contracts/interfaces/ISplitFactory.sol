// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Public surface of the split factory.
interface ISplitFactory {
    /// @notice Emitted once per created split.
    /// @param split The new split.
    /// @param payees The two payees, fixed forever.
    /// @param shares Their shares in basis points, fixed forever.
    /// @param creator The caller of `createSplit`.
    event SplitCreated(address indexed split, address[2] payees, uint16[2] shares, address indexed creator);

    /// @notice There is no split with this id.
    error UnknownSplit(uint256 id);

    /// @notice Number of splits created so far.
    function splitCount() external view returns (uint256);

    /// @notice The split with this id.
    function splits(uint256 id) external view returns (address);

    /// @notice True for every split created by this factory.
    function isSplit(address split) external view returns (bool);

    /// @notice Deploy a new immutable split.
    function createSplit(address[2] calldata payees, uint16[2] calldata sharesBps) external returns (address split);
}
