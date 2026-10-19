// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Errors} from "./Errors.sol";

library LibUtils {
    function to128(uint256 value) internal pure returns (uint128) {
        return SafeCast.toUint128(value);
    }

    function _packUnprocessedDeposit(uint256 midnightIndex, uint256 amount) internal pure returns (bytes32) {
        if (midnightIndex > type(uint128).max) revert Errors.ConversionExceedsUint128(midnightIndex);
        if (amount > type(uint128).max) revert Errors.ConversionExceedsUint128(amount);
        return bytes32((midnightIndex << 128) | amount);
    }

    function _unpackUnprocessedDeposit(bytes32 rec) internal pure returns (uint128 midnightIndex, uint128 amount) {
        midnightIndex = uint128(uint256(rec) >> 128); // high 128 bits
        amount = uint128(uint256(rec)); // low 128 bits
    }
}
