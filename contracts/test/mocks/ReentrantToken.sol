// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test-only token that, once armed, performs ONE arbitrary call (as itself) at the start of
/// the next `transfer` (or `transferFrom`) and records whether it succeeded and what it returned.
contract ReentrantToken is ERC20 {
    address public target;
    bytes public data;
    bool public onTransferFrom;
    bool public armed;
    bool public inCall;

    uint256 public calls;
    bool public lastOk;
    bytes public lastRet;

    constructor() ERC20("Reentrant", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address target_, bytes calldata data_, bool onTransferFrom_) external {
        target = target_;
        data = data_;
        onTransferFrom = onTransferFrom_;
        armed = true;
    }

    function _reenter() private {
        armed = false;
        calls += 1;
        (lastOk, lastRet) = target.call(data);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (armed && !onTransferFrom) _reenter();
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (armed && onTransferFrom) _reenter();
        return super.transferFrom(from, to, value);
    }
}
