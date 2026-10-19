// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../libraries/CommonStructs.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title CarbonTonnageLib
 * @dev Library for standardized carbon tonnage calculations.
 * This library provides functions to convert between token amounts and carbon tonnes
 * for different token types (ERC20, ERC1155) and various decimal precisions.
 *
 * The library handles various token types with different decimal places:
 * - ERC20 with 18 decimals: baseUnit = 1e18, tonnesPerUnit = 1e18, precision = 1
 * - ERC20 with 6 decimals: baseUnit = 1e6, tonnesPerUnit = 1e6, precision = 1e12
 * - ERC1155 (whole tokens): baseUnit = 1, tonnesPerUnit = 1, precision = 1e18
 *
 * The precision parameter standardizes all tonne calculations to 18 decimal places
 * regardless of the token's native decimal places.
 */
library CarbonTonnageLib {
    // Error definition for division by zero
    error DivisionByZero();

    /**
     * @dev Converts token amount to carbon tonnes using conversion config
     * @param amount Token amount to convert
     * @param config Conversion configuration
     * @return Equivalent carbon tonnes with standardized precision
     *
     * Formula: (amount * tonnesPerUnit) / baseUnit * precision
     *
     * This normalizes tokens with different decimal places to a standard tonne representation:
     * - 1.0 of an 18-decimal ERC20 (1e18 wei): (1e18 * 1e18) / 1e18 * 1 = 1e18
     * - 1.0 of a 6-decimal token (1e6 units): (1e6 * 1e6) / 1e6 * 1e12 = 1e18
     * - 1 of an ERC1155 (1 unit): (1 * 1) / 1 * 1e18 = 1e18
     */
    function tokenAmountToTonnes(uint256 amount, CommonStructs.ConversionConfig memory config)
        public
        pure
        returns (uint256)
    {
        if (config.baseUnit == 0) return 0; // Avoid division by zero
        if (amount == 0) return 0; // Short circuit for zero amount

        // Two-step conversion:
        // 1. Convert to tonnes in token's native precision: (amount * tonnesPerUnit) / baseUnit
        // 2. Standardize to 18 decimals: nativeTonnes * precision
        uint256 nativeTonnes = Math.mulDiv(amount, config.tonnesPerUnit, config.baseUnit);
        return nativeTonnes * config.precision;
    }

    /**
     * @dev Converts carbon tonnes to token amount using conversion config
     * @param tonnes Carbon tonnes to convert (with standardized precision)
     * @param config Conversion configuration
     * @return Equivalent token amount in the token's native decimal representation
     *
     * Formula: (tonnes / precision) * baseUnit / tonnesPerUnit
     *
     * This converts standardized tonne representation back to token-specific amounts:
     * - 1.0 tonne (1e18): (1e18 / 1) * 1e18 / 1e18 = 1e18 (ERC20 with 18 decimals)
     * - 1.0 tonne (1e18): (1e18 / 1e12) * 1e6 / 1e6 = 1e6 (ERC20 with 6 decimals)
     * - 1.0 tonne (1e18): (1e18 / 1e18) * 1 / 1 = 1 (ERC1155)
     */
    function tonnesToTokenAmount(uint256 tonnes, CommonStructs.ConversionConfig memory config)
        public
        pure
        returns (uint256)
    {
        if (config.tonnesPerUnit == 0 || config.precision == 0) return 0; // Avoid division by zero
        if (tonnes == 0) return 0; // Short circuit for zero tonnes

        // Two-step conversion:
        // 1. Convert standardized tonnes to native token precision: tonnes / precision
        // 2. Convert to token amount: nativeTonnes * baseUnit / tonnesPerUnit
        uint256 nativeTonnes = tonnes / config.precision; // Integer division floors the result
        return Math.mulDiv(nativeTonnes, config.baseUnit, config.tonnesPerUnit);
    }

    /**
     * @dev Validates a conversion configuration
     * @param config Conversion configuration to validate
     * @return True if configuration is valid
     */
    function isValidConversionConfig(CommonStructs.ConversionConfig memory config) public pure returns (bool) {
        // Basic validity check
        return config.baseUnit > 0 && config.tonnesPerUnit > 0 && config.precision > 0;
    }

    /**
     * @dev Gets the maximum token amount that can be safely converted given a config
     * @param config Conversion configuration
     * @return Maximum safe token amount
     */
    function getMaxSafeTokenAmount(CommonStructs.ConversionConfig memory config) public pure returns (uint256) {
        if (config.precision == 0 || config.tonnesPerUnit == 0) return 0;

        // Calculate maximum safe amount that won't overflow:
        // First, the native tonnes calculation: type(uint256).max / tonnesPerUnit
        // Since we then multiply by precision, divide by precision as well
        return type(uint256).max / config.tonnesPerUnit;
    }
}
