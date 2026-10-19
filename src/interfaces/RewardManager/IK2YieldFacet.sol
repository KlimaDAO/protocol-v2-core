// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRiskyYieldFacet} from "./IRiskyYieldFacet.sol";

interface IK2YieldFacet {
    struct Weight {
        uint256 maturityId;
        uint256 weight;
    }

    struct K2YDistribution {
        uint256 k2Stakers;
        uint256 kvcmStakers;
        uint256 treasury;
        uint256 kvcmK2LP;
        uint256 kvcmQLP;
    }

    struct MaturityYieldWithShares {
        uint256 maturityId;
        uint256 k2Yield;
        uint256 totalShares;
    }

    struct CalculateAGYieldParams {
        uint256 totalK2Yield;
        uint256 GSq;
        uint256 LSq;
        uint256 lambdaG;
        uint256 lambdaGG;
        uint256 utilisation;
    }

    struct CalculateAQYieldParams {
        uint256 totalK2Yield;
        uint256 GSq;
        uint256 LSq;
        uint256 lambdaQ;
        uint256 lambdaGG;
        uint256 utilisation;
    }

    struct K2YforK2StakersParams {
        uint256 totalK2Yield;
        uint256 kvcmStaked;
        uint256 L;
        uint256 G;
        uint256 utilisation;
    }

    struct K2YKVCMStakers {
        uint256 totalK2Yield;
        uint256 kvcmStaked;
        uint256 L;
        uint256 G;
        uint256 utilisation;
    }

    struct K2YforTreasuryParams {
        uint256 totalK2Yield;
        uint256 utilisation;
    }

    struct K2YieldProcessedIndices {
        uint128 lastProcessedMidnightIndexKVCM;
        uint128 lastProcessedMidnightIndexK2Stakers;
        uint128 lastProcessedMidnightIndexTreasury;
        uint128 lastProcessedMidnightIndexK2LP;
        uint128 lastProcessedMidnightIndexQLP;
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event LPK2YieldAccumulatorUpdated(
        address indexed lpToken,
        uint64 indexed midnightIndex,
        uint256 maturityId,
        uint256 totalRewards,
        uint256 accumulator
    );
    event KVCMK2YieldAccumulatorUpdated(
        uint64 indexed midnightIndex, uint256 maturityId, uint256 totalRewards, uint256 accumulator
    );
    event K2StakersK2YieldAccumulatorUpdated(uint64 indexed midnightIndex, uint256 totalRewards, uint256 accumulator);
    event K2YieldDistributedToTreasury(uint64 indexed midnightIndex, uint256 totalRewards);

    // ---------------------------------------------------------------------
    // Compute Functions
    // ---------------------------------------------------------------------
    function computeK2YDistribution(uint64 midNightIndex) external view returns (K2YDistribution memory distribution);
    function computeK2YForAQLPs(uint64 midNightIndex) external view returns (MaturityYieldWithShares[] memory yields);
    function computeK2YForAGLPs(uint64 midNightIndex) external view returns (MaturityYieldWithShares[] memory yields);
    function computeK2YDistributionForKVCMStakers(uint64 midNightIndex)
        external
        view
        returns (MaturityYieldWithShares[] memory yields);
    function computeK2YDistributionWithLambdas(uint64 midNightIndex, IRiskyYieldFacet.FinalizationValues memory lambdas)
        external
        view
        returns (K2YDistribution memory distribution);
    function computeK2YForAQLPsWithDistribution(uint64 midNightIndex, K2YDistribution memory distribution)
        external
        view
        returns (MaturityYieldWithShares[] memory yields);
    function computeK2YForAGLPsWithDistribution(uint64 midNightIndex, K2YDistribution memory distribution)
        external
        view
        returns (MaturityYieldWithShares[] memory yields);
    function computeK2YForKVCMStakersWithDistribution(uint64 midNightIndex, K2YDistribution memory distribution)
        external
        view
        returns (MaturityYieldWithShares[] memory yields);

    // WithSupply variants - accept KVCM circulatingSupply to avoid storage reads
    function computeK2YForAQLPsWithSupply(
        uint64 midNightIndex,
        K2YDistribution memory distribution,
        uint256 circulatingSupply
    ) external view returns (MaturityYieldWithShares[] memory yields);
    function computeK2YForAGLPsWithSupply(
        uint64 midNightIndex,
        K2YDistribution memory distribution,
        uint256 circulatingSupply
    ) external view returns (MaturityYieldWithShares[] memory yields);
    function computeK2YForKVCMStakersWithSupply(
        uint64 midNightIndex,
        K2YDistribution memory distribution,
        uint256 circulatingSupply
    ) external view returns (MaturityYieldWithShares[] memory yields);

    // ---------------------------------------------------------------------
    // Accumulator Update Functions
    // ---------------------------------------------------------------------
    function updateK2YAccForLPs(
        address lpToken,
        uint64 midNightIndex,
        MaturityYieldWithShares[] calldata maturityYields
    ) external;
    function updateK2YAccForKVCMStakers(uint64 midNightIndex, MaturityYieldWithShares[] memory yields) external;
    function updateK2YAccForK2Stakers(uint64 midNightIndex, uint256 totalK2YieldForK2Stakers, uint256 totalShares)
        external;
    function distributeK2YToTreasury(uint64 midNightIndex, uint256 totalK2YieldForTreasury) external;

    function getK2YieldLastProcessedIndices(address k2LP, address qLP)
        external
        view
        returns (K2YieldProcessedIndices memory);
}
