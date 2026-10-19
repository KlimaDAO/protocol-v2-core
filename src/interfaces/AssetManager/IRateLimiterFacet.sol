// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RateLimiterLib} from "src/libraries/aam/RateLimiterLib.sol";

interface IRateLimiterFacet {
    event DefaultKVCMRateUpdated(uint256 defaultKVCMRate);
    event DefaultK2RateUpdated(uint256 defaultK2Rate);
    event ClassMinEffectiveAllocationUpdated(address indexed carbonClass, uint256 kvcm, uint256 k2);

    /**
     * @notice Sets a class's minimum effective allocations. Allocation up to this amount counts toward swap
     * pricing instantly; above it, the effective allocation ramps at the limiter rate. Must be non-zero before
     * the class's allocation goes 0 -> non-zero, or that allocation reverts with MinEffectiveAllocationNotSet.
     * @param carbonClass The carbon class (must be registered)
     * @param kvcm Minimum effective KVCM allocation
     * @param k2 Minimum effective K2 allocation
     */
    function setClassMinEffectiveAllocation(address carbonClass, uint128 kvcm, uint128 k2) external;

    /**
     * @notice Returns a class's minimum effective allocations
     */
    function getMinEffectiveAllocation(address carbonClass) external view returns (uint256 kvcm, uint256 k2);

    function getRateLimiterSnapshotValues(address carbonClass)
        external
        view
        returns (RateLimiterLib.RateLimiterSnapshotValues memory);

    /* Staking Manager Only (external) */
    /**
     * @notice Updates the KVCM allocation rate limiter
     * @param carbonClass The carbon class to update the rate limiter for
     * @param preTxnKvcmAllocationValue The pre-transaction KVCM allocation value
     * @param amountIfZeroPreTxn Unused; kept for ABI compatibility
     */
    function updateKvcmAllocationRateLimiter(
        address carbonClass,
        uint256 preTxnKvcmAllocationValue,
        uint256 amountIfZeroPreTxn
    ) external;
    /**
     * @notice Updates the K2 allocation rate limiter
     * @param carbonClass The carbon class to update the rate limiter for
     * @param preTxnK2AllocationValue The pre-transaction K2 allocation value
     * @param amountIfZeroPreTxn Unused; kept for ABI compatibility
     */
    function updateK2AllocationRateLimiter(
        address carbonClass,
        uint256 preTxnK2AllocationValue,
        uint256 amountIfZeroPreTxn
    ) external;
}
