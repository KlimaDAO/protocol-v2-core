// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRollUpdateFacet} from "./IRollUpdateFacet.sol";
import {IRiskyYieldFacet} from "./IRiskyYieldFacet.sol";
import {IK2YieldFacet} from "./IK2YieldFacet.sol";

interface IBatchComputeFacet {
    /// @notice Aggregate struct containing all yield computations for an interval
    struct BatchYields {
        // Lock Yields (from RollUpdateFacet)
        IRollUpdateFacet.MaturityYields[] lockYields;
        uint256 circulatingSupply;
        uint256 discountParameter;
        // Finalized Lambdas
        IRiskyYieldFacet.FinalizationValues lambdas;
        // Risky Yield distribution
        IRiskyYieldFacet.RYDistribution ryDistribution;
        // K2 Yield distribution
        IK2YieldFacet.K2YDistribution k2yDistribution;
        // K2 stakers total shares (for update calls)
        uint256 k2StakersTotalShares;
        // RY LP Yields (per maturity breakdown for each LP token)
        IRiskyYieldFacet.LPMaturityYieldWithShares[] kvcmK2LpRyYields;
        IRiskyYieldFacet.LPMaturityYieldWithShares[] kvcmQLpRyYields;
        // K2Y LP Yields (per maturity breakdown)
        IK2YieldFacet.MaturityYieldWithShares[] aqLpK2Yields;
        IK2YieldFacet.MaturityYieldWithShares[] agLpK2Yields;
        IK2YieldFacet.MaturityYieldWithShares[] kvcmStakersK2Yields;
    }

    /// @notice Batch compute all yields for a midnight index in a single read-only call
    /// @dev Chains compute functions together passing intermediate values as params
    /// @param midnightIndex The target midnight index to compute yields for
    /// @return yields Aggregate struct with all computed yields
    function batchComputeAllYields(uint128 midnightIndex) external view returns (BatchYields memory yields);
}
