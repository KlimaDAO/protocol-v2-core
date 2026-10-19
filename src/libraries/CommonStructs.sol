// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title CommonStructs
 * @dev Library containing shared type definitions used across the carbon protocol
 */
library CommonStructs {
    // Enums
    enum TokenType {
        ERC20,
        ERC1155
    }

    // Structs
    struct ConversionConfig {
        uint64 baseUnit; // The base unit of the token (e.g., 1e18 for wei, 1e6 for micro)
        uint64 tonnesPerUnit; // How many tonnes one base unit represents
        uint64 precision; // Precision is a standardization factor for all tonne calculations
    }

    struct CreditConfig {
        TokenType tokenType;
        address tokenAddress;
        ConversionConfig conversion;
    }

    struct MaturityTonnes {
        uint256 maturityId;
        uint256 tonnes;
    }
}
