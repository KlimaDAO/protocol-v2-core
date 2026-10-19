// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetManagerStorage} from "src/libraries/storage/AssetManagerStorage.sol";
import {RateLimiterLib} from "src/libraries/aam/RateLimiterLib.sol";
import {Errors} from "src/libraries/Errors.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title RateLimiterSeedLib
 * @notice One-shot migration helper for seeding uninitialized allocation rate limiters. This should never live on the actual diamond, only in a script.
 *
 * @dev Repairs classes whose limiter state (0/0) was lost when the quote was removed, and re-registered.
 *      Ideally this should never happen again now with replaceQuoter() included.
 */
library RateLimiterSeedLib {
    /**
     * @param carbonClass The carbon class to seed
     * @param currentKvcmAllocation The class's current KVCM allocation
     * @param currentK2Allocation The class's current K2 allocation
     */
    function seedAllocationRateLimiters(address carbonClass, uint256 currentKvcmAllocation, uint256 currentK2Allocation)
        internal
    {
        AssetManagerStorage.ClassQuoterData storage classQuoterData =
            AssetManagerStorage.classQuoterLayout().quoters[RateLimiterLib.classQuoter(carbonClass)];

        uint256 nowTs = block.timestamp;

        AssetManagerStorage.RateLimiter storage kvcmLimiter = classQuoterData.kvcmAllocationRateLimiter;
        if (kvcmLimiter.snapshotValue == 0 && kvcmLimiter.lastUpdateTimestamp == 0) {
            if (currentKvcmAllocation == 0) revert Errors.ZeroAllocationForClass(carbonClass);
            if (kvcmLimiter.rate == 0) kvcmLimiter.rate = RateLimiterLib.getDefaultKVCMRate();
            kvcmLimiter.snapshotValue = SafeCast.toUint128(RateLimiterLib._initMinAllocation(currentKvcmAllocation));
            kvcmLimiter.lastUpdateTimestamp = SafeCast.toUint64(nowTs);
        }

        // K2 is optional per class; only seed when the class actually has a K2 allocation.
        AssetManagerStorage.RateLimiter storage k2Limiter = classQuoterData.k2AllocationRateLimiter;
        if (currentK2Allocation > 0 && k2Limiter.snapshotValue == 0 && k2Limiter.lastUpdateTimestamp == 0) {
            if (k2Limiter.rate == 0) k2Limiter.rate = RateLimiterLib.getDefaultK2Rate();
            k2Limiter.snapshotValue = SafeCast.toUint128(RateLimiterLib._initMinAllocation(currentK2Allocation));
            k2Limiter.lastUpdateTimestamp = SafeCast.toUint64(nowTs);
        }
    }
}
