// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AccountingToken is ERC20 {
    error Unauthorized();
    error NotAllowed();

    address public immutable ACCOUNTING;
    address public immutable TRACKED_ASSET;

    constructor(
        string memory name_,
        string memory symbol_,
        address trackedAsset,
        address accounting
    )
        ERC20(name_, symbol_)
    {
        TRACKED_ASSET = trackedAsset;
        ACCOUNTING = accounting;
    }

    modifier onlyAccounting() {
        if (msg.sender != ACCOUNTING) revert Unauthorized();
        _;
    }

    /**
     * @dev See {IERC20Metadata-decimals}.
     */
    function decimals() public view virtual override returns (uint8) {
        return IERC20Metadata(TRACKED_ASSET).decimals();
    }

    /**
     * @notice burn `burnAmount` from `burnAddress`
     * @param burnAddress address to burn from
     * @param burnAmount amount to burn
     */
    function burnFrom(address burnAddress, uint256 burnAmount) external onlyAccounting {
        _burn(burnAddress, burnAmount);
    }

    /**
     * @notice mints `mintAmount` to `mintAddress`
     * @param mintAddress address to mint to
     * @param mintAmount amount to mint
     */
    function mintTo(address mintAddress, uint256 mintAmount) external onlyAccounting {
        _mint(mintAddress, mintAmount);
    }

    /**
     * @dev should not ordinarily be transferred
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NotAllowed();
    }

    /**
     * @dev should not ordinarily be transferred
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NotAllowed();
    }
}
