// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Errors} from "../../libraries/Errors.sol";
import {Constants} from "../../libraries/Constants.sol";
import {UD60x18, ud, unwrap, div, ln, inv, exp, pow, powu} from "@prb/math/UD60x18.sol";
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library KvcmIncentivesCurveMathLib {
    /**
     * @notice Calculate the E value for a given maturity timestamp and current timestamp.
     * @param maturityTimestamp The maturity timestamp.
     * @param currentTimestamp The current timestamp.
     * @return E The E value.
     */
    function calculateE(uint256 maturityTimestamp, uint256 currentTimestamp) internal pure returns (uint256 E) {
        if (maturityTimestamp < currentTimestamp) {
            E = 0;
        } else {
            E = (maturityTimestamp - currentTimestamp) * Constants.WAD / Constants.YEAR;
        }
    }

    /**
     * @notice Calculate the E value snapped up to whole maturity periods.
     * @param maturityTimestamp The maturity timestamp.
     * @param currentTimestamp The current timestamp.
     * @param maturityPeriod The maturity period in seconds.
     * @return E The E value in whole maturity periods remaining, rounded up, as a fraction of a year (WAD).
     */
    function calculateGridAlignedE(uint256 maturityTimestamp, uint256 currentTimestamp, uint256 maturityPeriod)
        internal
        pure
        returns (uint256 E)
    {
        if (maturityTimestamp <= currentTimestamp) return 0;
        uint256 intervals = Math.ceilDiv(maturityTimestamp - currentTimestamp, maturityPeriod);
        E = (intervals * maturityPeriod) * Constants.WAD / Constants.YEAR;
    }

    /**
     * @notice Calculate the gamma value for a given D, C, and E.
     * @param D The D value.
     * @param C The C value.
     * @param E The E value.
     * @return gamma The gamma value.
     */
    function calculateGamma(uint256 D, uint256 C, uint256 E) internal pure returns (uint256 gamma) {
        // If a spot bucket (E==0) or D or C are 0, this bucket’s gamma contributes nothing.
        if (E == 0 || D == 0 || C == 0) return 0;
        uint256 term1 = (E * Constants.WAD) / D;
        uint256 term2 = (E * E) / (2 * C);
        gamma = term1 > term2 ? term1 - term2 : 0;
    }

    /**
     * @notice Calculate the normalized gamma cumulative sum for a given D, C, and E.
     * @param D The D value.
     * @param C The C value.
     * @param numMaturities The number of maturities.
     * @param maturityPeriod The maturity period.
     * @param firstActiveMaturityId The first active maturity id.
     * @param firstActiveMaturityTimestamp The first active maturity timestamp.
     * @param currentTimestamp The current timestamp.
     * @param maturityId The maturity id.
     * @return gammaCumulativeSum The normalized gamma cumulative sum.
     */
    function calculateNormalizedGammaCumulativeSum(
        uint256 D,
        uint256 C,
        uint256 numMaturities,
        uint256 maturityPeriod,
        uint256 firstActiveMaturityId,
        uint256 firstActiveMaturityTimestamp,
        uint256 currentTimestamp,
        uint256 maturityId
    ) internal pure returns (uint256 gammaCumulativeSum) {
        uint256 gammaSum = 0;
        uint256 lastMaturityId = firstActiveMaturityId + numMaturities - 1;

        // this should never hit due to earlier validations
        if (maturityId > lastMaturityId) {
            revert Errors.InvalidMaturityId(maturityId);
        }

        for (uint256 i = 0; i < numMaturities; ++i) {
            uint256 Ei = calculateGridAlignedE(
                firstActiveMaturityTimestamp + (i * maturityPeriod), currentTimestamp, maturityPeriod
            );
            uint256 gamma = calculateGamma(D, C, Ei);
            gammaSum += gamma;
        }

        if (gammaSum == 0) {
            revert Errors.ZeroGammaSum();
        }

        uint256 runningCumulativeGamma = 0;

        for (uint256 i = 0; i < numMaturities; ++i) {
            uint256 Ei = calculateGridAlignedE(
                firstActiveMaturityTimestamp + (i * maturityPeriod), currentTimestamp, maturityPeriod
            );
            uint256 gamma = calculateGamma(D, C, Ei);
            // normalize + accumulate
            runningCumulativeGamma += gamma * Constants.WAD / gammaSum;

            if (i + firstActiveMaturityId == maturityId) {
                return runningCumulativeGamma;
            }
        }
    }

    /**
     * @notice Calculate the discount factor for a given zero coupon yield and maturity E.
     * @param zeroCouponYield The zero coupon yield.
     * @param maturityE The maturity E.
     * @return discountFactor The discount factor.
     */
    function calculateDiscountFactor(uint256 zeroCouponYield, uint256 maturityE)
        internal
        pure
        returns (uint256 discountFactor)
    {
        uint256 expVal = (zeroCouponYield * maturityE) / Constants.WAD;
        UD60x18 expResult = exp(ud(expVal));
        discountFactor = unwrap(inv(expResult));
    }

    /**
     * @notice Calculate the zero coupon yield for a given total locked proportion, gamma cumulative sum, and maturity E.
     * @param totalLockedProportion The total locked proportion.
     * @param gammaCumulativeSum The gamma cumulative sum.
     * @param maturityE The maturity E.
     * @return zeroCouponYield The zero coupon yield.
     */
    function calculateZeroCouponYield(uint256 totalLockedProportion, uint256 gammaCumulativeSum, uint256 maturityE)
        internal
        pure
        returns (uint256 zeroCouponYield)
    {
        // When E == 0 (spot bucket), Z must be 0 and we must not divide by 0.
        if (maturityE == 0) return 0;
        zeroCouponYield = ((Constants.WAD - totalLockedProportion) * gammaCumulativeSum) / maturityE;
    }

    /**
     * @notice Calculate the Yt value for a given zero coupon yield.
     * @param zeroCouponYield The zero coupon yield.
     * @return Yt The Yt value.
     */
    function calculateYt(uint256 zeroCouponYield) internal pure returns (uint256 Yt) {
        UD60x18 zcYield = ud(zeroCouponYield);
        /**
         * @custom:note @dev should this be configurable? hardcoded in model.
         * Otherwise we should hardcode yieldDistributionInterval everywhere else as well.
         */
        Yt = unwrap(exp(div(zcYield, ud(Constants.DAYS_IN_YEAR * Constants.WAD))) - ud(1e18));
    }

    /**
     * @notice Calculate the bucket lock yield for a given zero coupon yield and bucket total locked.
     * @param zeroCouponYield The zero coupon yield.
     * @param bucketTotalLocked The bucket total locked.
     * @return deltaForCurrentPeriod The delta for the current period.
     * @return yieldForCurrentInterval The yield for the current interval.
     */
    function calculateBucketLockYieldForPeriod(uint256 zeroCouponYield, uint256 bucketTotalLocked)
        internal
        pure
        returns (uint256 deltaForCurrentPeriod, uint256 yieldForCurrentInterval)
    {
        deltaForCurrentPeriod = calculateYt(zeroCouponYield);
        yieldForCurrentInterval = Math.mulDiv(deltaForCurrentPeriod, bucketTotalLocked, Constants.WAD);
    }

    /**
     * @notice Get the price per share at a given midnight index and maturity id.
     * @param midnightIndex The midnight index.
     * @param maturityId The maturity id.
     * @return pps The price per share.
     */
    function getPricePerShareAtMidnightIndex(uint256 midnightIndex, uint256 maturityId)
        internal
        view
        returns (uint256)
    {
        RewardManagerStorage.KvcmLockYieldLayout storage yl = RewardManagerStorage.kvcmLockYieldLayout();
        uint256 pps = yl.maturityIntervalData[midnightIndex][maturityId].ppsAtRoll;

        if (pps == 0) {
            revert Errors.PPSNotSet(midnightIndex, maturityId);
        }
        return pps;
    }
}
