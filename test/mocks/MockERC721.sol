// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    uint256 private _nextTokenId;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) { }

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
