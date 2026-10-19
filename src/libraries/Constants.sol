// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library Constants {
    uint256 constant WAD = 1e18;
    uint256 constant YEAR = 365 days;
    uint256 constant DAYS_IN_YEAR = 365;

    uint256 constant UD_EXP_MAX_INPUT = 133_084_258_667_509_499_440;

    uint64 constant DEFAULT_KVCM_RATE = 8022536812036; // 1e18 * ln(2) / 1 day
    uint64 constant DEFAULT_K2_RATE = 192540883488874; // 1e18 * ln(2) / 1 hour

    // RewardManager
    uint256 constant LOCK_MIN_AMOUNT = 1e18;
    uint256 constant LOCK_MAX_AMOUNT = 1e27;
    uint256 constant K2_LOCK_PERIOD = 1 days;

    uint128 constant YIELD_DISTRIBUTION_INTERVAL = 1 days;
    uint256 constant LAMBDA_SCALE = 1e9;

    uint256 constant SQRT2_18 = 1_414_213_562_373_095_048;
}
