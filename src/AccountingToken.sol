// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// TODO maybe permissioned transfers
contract AccountingToken is ERC20 {
    error Unauthorized();

    address public immutable ACCOUNTING;

    constructor(string memory name_, string memory symbol_, address accounting) ERC20(name_, symbol_) {
        ACCOUNTING = accounting;
    }

    modifier onlyAccounting() {
        if (msg.sender != ACCOUNTING) revert Unauthorized();
        _;
    }

    /**
     * @notice burn `_burnAmount` from `_burnAddress`
     * @param burnAddress address to burn from
     * @param burnAmount amount to burn
     */
    function burnFrom(address burnAddress, uint256 burnAmount) external onlyAccounting {
        _burn(burnAddress, burnAmount);
    }

    /**
     * @notice mints `_mintAmount` to `_mintAddress`
     * @param mintAddress address to mint to
     * @param mintAmount amount to mint
     */
    function mintTo(address mintAddress, uint256 mintAmount) external onlyAccounting {
        _mint(mintAddress, mintAmount);
    }
}
