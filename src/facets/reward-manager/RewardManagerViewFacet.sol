// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// interfaces
import {IRewardManagerViewFacet} from "src/interfaces/RewardManager/IRewardManagerViewFacet.sol";
import {IRewardManager} from "src/interfaces/RewardManager/IRewardManager.sol";
import {IMaturityManager} from "src/interfaces/IMaturityManager.sol";
// libraries
import {DiscountFactorStorage64} from "src/libraries/storage/DiscountFactorStorage64.sol";

import {RewardManagerStorage} from "src/libraries/storage/RewardManagerStorage.sol";
import {LibUtils} from "src/libraries/LibUtils.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

/**
 * @title RewardManagerViewFacet
 * @dev Facet for viewing reward manager data
 */
contract RewardManagerViewFacet is IRewardManagerViewFacet {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    function getKvcmLock(uint256 lockId) external view returns (RewardManagerStorage.KvcmLockView memory) {
        RewardManagerStorage.KvcmLock storage lock = RewardManagerStorage.kvcmLocksLayout().kvcmLocks[lockId];

        uint128[][] memory unprocessedDeposits = new uint128[][](lock.unprocessedDeposits.length());

        for (uint256 i = 0; i < lock.unprocessedDeposits.length(); i++) {
            uint128[] memory deposit = new uint128[](2);
            bytes32 depositRecord = lock.unprocessedDeposits.at(i);

            (uint128 midnightIndex, uint128 amount) = LibUtils._unpackUnprocessedDeposit(depositRecord);
            deposit[0] = midnightIndex;
            deposit[1] = amount;
            unprocessedDeposits[i] = deposit;
        }

        RewardManagerStorage.KvcmLockView memory lockView;
        lockView.maturityId = lock.maturityId;
        lockView.midnightIndexStart = lock.midnightIndexStart;
        lockView.unprocessedDeposits = unprocessedDeposits;
        lockView.rawPrincipal = lock.rawPrincipal;
        lockView.shares = lock.shares;
        lockView.status = lock.status;
        lockView.yieldDistributed = lock.yieldDistributed;

        return lockView;
    }

    /**
     * @dev Get the discount factor for a given maturity id at a given midnight index
     * @param midnightIndex The midnight index
     * @param maturityId The maturity id
     * @return discountFactor The discount factor
     */
    function getDiscountFactor(uint256 midnightIndex, uint256 maturityId)
        external
        view
        returns (uint64 discountFactor)
    {
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();
        DiscountFactorStorage64.PackedDiscountFactorsLayout storage discountFactorsLayout =
            yieldLayout.discountFactors[midnightIndex];
        return DiscountFactorStorage64._get(discountFactorsLayout, maturityId);
    }

    function getDiscountFactors(uint256 midnightIndex)
        external
        view
        returns (IRewardManager.MaturityDiscountFactor[] memory discountFactors, uint256[] memory activeMaturities)
    {
        (uint256 firstMaturityId, uint256 lastMaturityId) =
            IMaturityManager(RewardManagerStorage.rmConfig().maturityManager).getActiveMaturityRange();

        uint256 numMaturities = lastMaturityId - firstMaturityId + 1;

        activeMaturities = new uint256[](numMaturities);
        discountFactors = new IRewardManager.MaturityDiscountFactor[](numMaturities);

        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();

        DiscountFactorStorage64.PackedDiscountFactorsLayout storage discountFactorsLayout =
            yieldLayout.discountFactors[midnightIndex];

        for (uint256 i = 0; i < numMaturities; i++) {
            uint64 factor = DiscountFactorStorage64._get(discountFactorsLayout, firstMaturityId + i);
            discountFactors[i] =
                IRewardManager.MaturityDiscountFactor({maturityId: firstMaturityId + i, discountFactor: factor});

            activeMaturities[i] = firstMaturityId + i;
        }

        return (discountFactors, activeMaturities);
    }

    function getLastMidnightIndexYieldDistribution() external view returns (uint256) {
        return RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution;
    }

    function getIntervalSettled(uint256 midnightIndex) external view returns (bool) {
        return RewardManagerStorage.kvcmLockYieldLayout().intervalData[midnightIndex].settled;
    }

    function getCurrentMaturityTotals(uint256 maturityId)
        external
        view
        returns (uint256 totalRawPrincipal, uint256 totalSharesForMaturity)
    {
        return (
            RewardManagerStorage.kvcmLockYieldLayout().currentMaturityTotals[maturityId].totalRawPrincipal,
            RewardManagerStorage.kvcmLockYieldLayout().currentMaturityTotals[maturityId].totalSharesForMaturity
        );
    }

    // =============================================================================
    // DEBUG VIEW FUNCTIONS
    // =============================================================================

    function getLPRYAccSnapshot(address lpToken, uint256 maturityId, uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory)
    {
        return RewardManagerStorage.rmStorage().lpRYieldAccSnapshot[lpToken][maturityId][midnightIndex];
    }

    function getLPK2YAccSnapshot(address lpToken, uint256 maturityId, uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory)
    {
        return RewardManagerStorage.rmStorage().lpK2YieldAccSnapshot[lpToken][maturityId][midnightIndex];
    }

    function getK2RYAccSnapshot(uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory)
    {
        return RewardManagerStorage.rmStorage().k2RYieldAccSnapshot[midnightIndex];
    }

    function getK2K2YAccSnapshot(uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory)
    {
        return RewardManagerStorage.rmStorage().k2K2YieldAccSnapshot[midnightIndex];
    }

    function getKVCMK2YAccSnapshot(uint256 maturityId, uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory)
    {
        return RewardManagerStorage.rmStorage().kvcmK2YieldAccSnapshot[maturityId][midnightIndex];
    }

    function getIntervalData(uint256 midnightIndex) external view returns (RewardManagerStorage.IntervalData memory) {
        return RewardManagerStorage.kvcmLockYieldLayout().intervalData[midnightIndex];
    }

    function getMaturityIntervalData(uint256 midnightIndex, uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.MaturityIntervalData memory)
    {
        return RewardManagerStorage.kvcmLockYieldLayout().maturityIntervalData[midnightIndex][maturityId];
    }

    function getFullMaturityTotals(uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.MaturityTotals memory)
    {
        return RewardManagerStorage.kvcmLockYieldLayout().currentMaturityTotals[maturityId];
    }
}
