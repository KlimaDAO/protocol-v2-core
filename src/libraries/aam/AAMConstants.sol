// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library AAMConstants {
    enum TokenType {
        ERC20,
        ERC1155
    }

    // *************
    // globals
    // *************

    // scaling factor
    uint256 public constant SCALING_FACTOR = 1e18;
    // maxUint256
    uint256 public constant MAX_UINT256 = type(uint256).max;

    // *************
    // swap limits
    // *************

    // 1 kg minimum
    uint256 public constant MIN_TONNAGE_AMOUNT = 1e15;
    // 1B tonnes maximum
    uint256 public constant MAX_TONNAGE_AMOUNT = 1e27;
}
