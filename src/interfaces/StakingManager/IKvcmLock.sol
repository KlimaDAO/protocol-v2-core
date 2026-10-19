// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IKvcmLock is IERC721 {
    function mint(address to, uint256 tokenId, string memory uri) external;
    function burn(uint256 tokenId) external;
}
