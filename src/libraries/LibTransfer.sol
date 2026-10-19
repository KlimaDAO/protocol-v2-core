// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "./Errors.sol";
import {CommonStructs} from "./CommonStructs.sol";

library LibTransfer {
    using SafeERC20 for IERC20;

    function receiveToken(
        CommonStructs.TokenType tokenType,
        address token,
        uint256 tokenId,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;

        if (from == to) return;

        if (from == address(0) || to == address(0)) revert Errors.ZeroAddressNotAllowed();

        if (tokenType == CommonStructs.TokenType.ERC20) {
            IERC20(token).safeTransferFrom(from, to, amount);
        } else {
            IERC1155(token).safeTransferFrom(from, to, tokenId, amount, "");
        }
    }
}
