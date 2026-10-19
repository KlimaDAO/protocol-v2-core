// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";

interface IRiskyYieldFacet {
    enum StakeAction {
        Stake,
        Unstake
    }

    struct Weight {
        uint256 maturityId;
        uint256 weight;
    }

    // ---------------------------------------------------------------------
    // Structs
    // ---------------------------------------------------------------------
    struct LambdaGGParams {
        uint256 totalK2Allocations;
        uint256 k2InAGPool;
        uint256 kvcmInAQPool;
        uint256 kvcmSupply;
    }

    struct LambdaGParams {
        uint256 lambdaGG;
        uint256 kvcmInAGPool;
        uint256 kvcmInAQPool;
    }

    struct LambdaQParams {
        uint256 lambdaGG;
        uint256 lambdaG;
    }

    struct RYDistribution {
        uint256 k2StakersDistribution;
        uint256 kvcmK2LP;
        uint256 kvcmQLP;
    }

    struct LPMaturityYield {
        uint256 maturityId;
        uint256 riskyYield;
    }

    struct UpdateRewardsProportionsParams {
        uint256 totalK2Allocations;
    }

    struct LPMaturityYieldWithShares {
        uint256 maturityId;
        uint256 riskyYield;
        uint256 totalShares;
    }

    struct FinalizationValues {
        uint256 finalGG;
        uint256 finalG;
        uint256 finalQ;
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event RiskyYieldRewardsGenerated(uint256 totalRiskyYieldRewards, uint64 midNightIndex);
    event LPRiskyYieldAccumulatorUpdated(
        address indexed lpToken,
        uint64 indexed midnightIndex,
        uint256 maturityId,
        uint256 totalRewards,
        uint256 accumulator
    );
    event K2StakersRYAccumulatorUpdated(uint64 indexed midnightIndex, uint256 totalRewards, uint256 accumulator);
    event LambdasFinalized(uint64 indexed midnightIndex, uint256 finalGG, uint256 finalG, uint256 finalQ);
    event LambdaCacheRepaired(uint64 indexed midnightIndex);

    // ---------------------------------------------------------------------
    // Beta Update Functions
    // ---------------------------------------------------------------------

    function updateBetaSqForKvcmAllocation(uint256 kvcmAllocation_, address carbonClass_, uint64 midnightIndex_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForKvcmDeallocation(uint256 kvcmAllocation_, address carbonClass_, uint64 midnightIndex_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForKvcmSupplyIncrease(uint256 kvcmSupplyChange_, address carbonClass_, uint64 midnightIndex_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForKvcmSupplyDecrease(uint256 kvcmSupplyChange_, address carbonClass_, uint64 midnightIndex_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForK2Allocation(uint256 k2Allocation_, address carbonClass_, uint64 midnightIndex_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForK2Deallocation(uint256 k2Allocation_, address carbonClass_, uint64 midnightIndex_)
        external
        returns (uint256 betaSq);
    function setBetaSqForDay(uint64 midnightIndex, uint256 betaSq) external;

    // ---------------------------------------------------------------------
    // Lambda Functions
    // ---------------------------------------------------------------------
    function computeFinalizedLambdas(uint256 midNightIndex) external view returns (FinalizationValues memory values);
    function setFinalizedLambdas(uint64 midNightIndex, FinalizationValues calldata values) external;
    function repairFinalizedLambdaCache(uint64 midnightIndex) external;

    // ---------------------------------------------------------------------
    // Rewards Functions
    // ---------------------------------------------------------------------
    function updateRewardsProportions(uint256 midNightIndex, uint256 totalK2Allocations) external;

    // ---------------------------------------------------------------------
    // Getter Functions
    // ---------------------------------------------------------------------
    function getBeta(uint64 midnightIndex) external view returns (uint256);
    function getLastProcessedMidnightIndexForLP(address lpToken) external view returns (uint256);
    function getLastProcessedMidnightIndexForK2() external view returns (uint256);
    function getAllLastProcessedMidnightIndices(address kvcmK2LP, address kvcmQLP)
        external
        view
        returns (uint256 kvcmK2LPLastProcessed, uint256 kvcmQLPLastProcessed, uint256 k2LastProcessed);
    function getK2StakersTotalShares() external view returns (uint256 totalShares);

    function getDailyLambdaCache(uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.DailyLambdaCache memory);

    function getBetaSqCache(uint256 midnightIndex) external view returns (uint256);

    function getLastNonZeroBetaSqIndex() external view returns (uint256);

    function getRYBetaCache(address carbonClass) external view returns (RewardManagerStorage.RYBetaCache memory);

    // ---------------------------------------------------------------------
    // Compute Functions
    // ---------------------------------------------------------------------
    function computeBetaSqForCarbonClasses(address[] calldata carbonClasses) external view returns (uint256 betaSq);
    function computeRYWithLambda(uint256 kVCMYield, uint256 discountParam, FinalizationValues memory lambdas)
        external
        pure
        returns (RYDistribution memory distribution);

    // WithSupply variants - accept KVCM circulatingSupply to avoid storage reads
    function computeRYForLPsWithSupply(
        address lpToken,
        uint256 midnightIndex,
        RYDistribution memory distribution,
        uint256 circulatingSupply
    ) external view returns (LPMaturityYieldWithShares[] memory result);

    // ---------------------------------------------------------------------
    // Accumulator Update Functions
    // ---------------------------------------------------------------------
    function updateAccForLP(address lpToken, uint256 midnightIndex, LPMaturityYieldWithShares[] calldata maturityYields)
        external;
    function updateAccForK2Stakers(uint256 midnightIndex, uint256 k2StakersRewards, uint256 totalShares) external;
}
