// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IStakingManagerViewFacet} from "../../interfaces/StakingManager/IStakingManagerViewFacet.sol";
import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IRewardManagerViewFacet} from "../../interfaces/RewardManager/IRewardManagerViewFacet.sol";
import {StakingManagerStorage} from "../../libraries/storage/StakingManagerStorage.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract StakingManagerViewFacet is IStakingManagerViewFacet {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    function validateExpiredMaturityCleanup(StakingManagerStorage.StakingManagerConfigLayout storage sConfig)
        internal
        view
        returns (bool processingComplete, uint256 lastProcessedMidnightIndex, uint256 firstInactiveMaturityId)
    {
        // get first active maturity id
        (uint256 start,) = IMaturityManager(sConfig.maturityManager).getActiveMaturityRange();

        if (start <= 1) {
            return (true, lastProcessedMidnightIndex, 0);
        }

        firstInactiveMaturityId = start - 1;

        uint256 firstInactiveMidnightIndex =
            IMaturityManager(sConfig.maturityManager).getMidnightIndexForMaturityId(firstInactiveMaturityId);

        lastProcessedMidnightIndex =
            IRewardManagerViewFacet(sConfig.rewardManager).getLastMidnightIndexYieldDistribution();

        if (firstInactiveMidnightIndex > lastProcessedMidnightIndex) {
            return (false, lastProcessedMidnightIndex, firstInactiveMaturityId);
        }

        return (true, lastProcessedMidnightIndex, firstInactiveMaturityId); // trigger has cleaned up expired maturity allocations
    }

    function getAllocationsForClass(address carbonClass) external view returns (ClassAllocations memory) {
        /**
         * if the midnight index has not reached the first inactive maturity,
         * we need to remove class allocations for the expired maturities the trigger has not cleaned up
         */

        StakingManagerStorage.StakingManagerConfigLayout storage sConfig = StakingManagerStorage.configLayout();
        StakingManagerStorage.KvcmStakingLayout storage sKvcm = StakingManagerStorage.kvcmStakingLayout();

        (bool processingComplete, uint256 lastProcessedMidnightIndex, uint256 firstInactiveMaturityId) =
            validateExpiredMaturityCleanup(sConfig);

        uint256 kvcmAllocationCleanUpAmount = 0;

        if (!processingComplete) {
            // init at 1 because we know we need to clean at least one maturity
            uint256 maturitiesToClean = 1;

            // walk backward until we determine last midnight index that has been processed
            while (
                lastProcessedMidnightIndex
                    < IMaturityManager(sConfig.maturityManager)
                        .getMidnightIndexForMaturityId(firstInactiveMaturityId - maturitiesToClean)
            ) {
                maturitiesToClean++;
            }

            // remove class allocations in priceAllocationsByMaturity for the expired maturities
            for (uint256 i = 0; i < maturitiesToClean; i++) {
                EnumerableMap.AddressToUintMap storage m =
                    sKvcm.priceAllocationsByMaturity[SafeCast.toUint128(firstInactiveMaturityId - i)];

                (bool ok, uint256 allocationAmount) = m.tryGet(carbonClass);
                if (ok) kvcmAllocationCleanUpAmount += allocationAmount;
            }
        }

        uint256 kvcmStaked = sKvcm.allocationsByCarbonClass[carbonClass] > kvcmAllocationCleanUpAmount
            ? sKvcm.allocationsByCarbonClass[carbonClass] - kvcmAllocationCleanUpAmount
            : 0;
        uint256 k2Staked = StakingManagerStorage.k2StakingLayout().allocationsByCarbonClass[carbonClass];

        return ClassAllocations(carbonClass, kvcmStaked, k2Staked);
    }

    function getK2Locked() external view returns (uint256) {
        return StakingManagerStorage.k2StakingLayout().totalK2Locked;
    }

    function getKvcmLocked() external view returns (uint256) {
        return StakingManagerStorage.kvcmStakingLayout().totalKvcmLocked;
    }
}
