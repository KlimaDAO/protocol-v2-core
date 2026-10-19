// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRollUpdateFacet {
    /**
     * @notice Yield distribution settled event.
     * @param totalYieldToMint The total yield to mint.
     * @param midnightIndex The midnight index.
     * @param timestamp The timestamp.
     * @param discountParameter The discount parameter.
     * @param circulatingSupply The circulating supply.
     */
    event YieldDistributionSettled(
        uint256 totalYieldToMint,
        uint256 indexed midnightIndex,
        uint256 timestamp,
        uint256 discountParameter,
        uint256 circulatingSupply
    );

    /**
     * @notice Maturity roll settled event.
     * @param maturityId The maturity id.
     * @param midnightIndex The midnight index.
     * @param yieldForCurrentInterval The yield for the current interval.
     * @param ppsAtRoll The pps at roll.
     * @param totalSharesAtRoll The total shares at roll.
     */
    event MaturityRollSettled(
        uint256 midnightIndex,
        uint256 indexed maturityId,
        uint256 yieldForCurrentInterval,
        uint256 ppsAtRoll,
        uint256 totalSharesAtRoll
    );

    /**
     * @notice Maturity yields.
     * @dev passed to distributeKvcmLockYieldForInterval
     * @param midnightIndex The midnight index.
     * @param maturityId The maturity id.
     * @param rawLockIssueForInterval The raw lock issue for the current interval.
     * @param zeroCouponYield The zero coupon yield.
     */
    struct MaturityYields {
        uint256 midnightIndex;
        uint256 maturityId;
        uint256 rawLockIssueForInterval;
        uint256 zeroCouponYieldCurve;
        uint256[50] _gap;
    }

    /**
     * @notice Parameters for building the yield curve.
     * @param maturityEs Maturity E values.
     * @param maturityBucketKvcmLocked The maturity bucket kvcm locked.
     * @param gammas The gammas.
     * @param gammaSum The gamma sum.
     * @param firstActiveMaturityId The first active maturity id.
     * @param totalLockedProportion The total locked proportion.
     * @dev used in _buildCurve
     */
    struct BuildCurveParams {
        uint256[] maturityEs;
        uint256[] maturityBucketKvcmLocked;
        uint256[] gammas;
        uint256 gammaSum;
        uint256 firstActiveMaturityId;
        uint256 totalLockedProportion;
        uint256 circulatingSupply;
    }

    /**
     * @notice Intermediate state for dynamic forward swap pricing.
     * @param maturityId The maturity id of this point
     * @param discountFactor The discount factor for this point
     * @param zeroCouponYieldCurve The zero coupon yield curve for this point
     * @param unscaledLockIssue The unscaled lock issue for this point
     */
    struct YieldCurvePoint {
        uint256 maturityId;
        uint256 discountFactor;
        uint256 zeroCouponYieldCurve;
        uint256 yieldForCurrentInterval;
        uint256 deltaForCurrentPeriod;
        uint256 totalKvcmLockedForBucket;
    }

    /**
     * @notice Calculate the kvcm lock yield for the interval.
     * @param midnightIndex The midnight index.
     * @return yields The maturity yields.
     * @return currentCirculatingSupply The current circulating supply.
     * @return discountParameter The discount parameter.
     */
    function computeDayAheadLockYieldsAtIndex(uint128 midnightIndex)
        external
        view
        returns (MaturityYields[] memory yields, uint256 currentCirculatingSupply, uint256 discountParameter);

    /**
     * @notice Distribute the kvcm lock yield for the interval.
     * @param midnightIndex The midnight index.
     * @param discountParameter The discount parameter.
     * @param circulatingSupplySnapshot The circulating supply snapshot.
     * @param maturityYields The maturity yields.
     */
    function distributeKvcmLockYieldForInterval(
        uint256 midnightIndex,
        uint256 discountParameter,
        uint256 circulatingSupplySnapshot,
        MaturityYields[] memory maturityYields
    ) external;

    /**
     * @notice Get the full curve values for the interval.
     * @param targetMidnightIndex The target midnight index.
     * @param referenceTimestamp The reference timestamp.
     * @return yieldCurve The yield curve.
     * @return totalEffectiveKvcmLocked The total effective kvcm locked.
     * @return discountParameter The discount parameter.
     * @return yieldForCurrentInterval The unscaled total lock issue.
     */
    function getFullCurveValuesForInterval(uint256 targetMidnightIndex, uint256 referenceTimestamp)
        external
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalEffectiveKvcmLocked,
            uint256 discountParameter,
            uint256 yieldForCurrentInterval
        );

    /**
     * @notice Get the full curve values for the interval using provided circulating supply.
     * @dev Use this when circulatingSupply is already computed (e.g., from computeDayAheadLockYieldsAtIndex)
     * @param targetMidnightIndex The target midnight index.
     * @param referenceTimestamp The reference timestamp.
     * @param circulatingSupply The circulating supply to use for calculations.
     * @return yieldCurve The yield curve.
     * @return totalEffectiveKvcmLocked The total effective kvcm locked.
     * @return discountParameter The discount parameter.
     * @return yieldForCurrentInterval The yield for current interval.
     */
    function getFullCurveValuesForIntervalWithSupply(
        uint256 targetMidnightIndex,
        uint256 referenceTimestamp,
        uint256 circulatingSupply
    )
        external
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalEffectiveKvcmLocked,
            uint256 discountParameter,
            uint256 yieldForCurrentInterval
        );
    /**
     * @notice Returns the full active curve for the day ahead, based on previous day locks.
     * @dev Must be called with a specific block number to return the correct current circ supply
     * @return yieldCurve The yield curve values
     * @return totalEffectiveKvcmLocked The total effective kvcm locked
     * @return discountParameter The unscaled discount parameter
     * @return yieldForCurrentInterval The yield for the current interval
     */
    function getFullCurveValues()
        external
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalEffectiveKvcmLocked,
            uint256 discountParameter,
            uint256 yieldForCurrentInterval
        );
}
