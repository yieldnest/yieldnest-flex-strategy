// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { ERC20 } from "@yieldnest-vault/Common.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
        _mint(msg.sender, 1_000_000 * (10 ** uint256(decimals_)));
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
