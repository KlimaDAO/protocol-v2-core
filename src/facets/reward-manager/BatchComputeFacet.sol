// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {IBatchComputeFacet} from "../../interfaces/RewardManager/IBatchComputeFacet.sol";
import {IRollUpdateFacet} from "../../interfaces/RewardManager/IRollUpdateFacet.sol";
import {IRiskyYieldFacet} from "../../interfaces/RewardManager/IRiskyYieldFacet.sol";
import {IK2YieldFacet} from "../../interfaces/RewardManager/IK2YieldFacet.sol";

/**
 * @title BatchComputeFacet
 * @notice Batches all yield compute operations into a single read-only call
 * @dev Chains compute functions together, passing intermediate values as params
 *      to avoid storage dependencies on settled intervals and finalized lambdas
 */
contract BatchComputeFacet is IBatchComputeFacet {
    // ---------------------------------------------------------------------
    // Main Entry Point
    // ---------------------------------------------------------------------

    /// @inheritdoc IBatchComputeFacet
    function batchComputeAllYields(uint128 midnightIndex) external view returns (BatchYields memory yields) {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint64 idx = SafeCast.toUint64(midnightIndex);

        // Compute lock yields (already view, no storage dependencies)
        (
            IRollUpdateFacet.MaturityYields[] memory lockYields,
            uint256 kvcmCirculatingSupply,
            uint256 discountParameter
        ) = IRollUpdateFacet(address(this)).computeDayAheadLockYieldsAtIndex(midnightIndex);

        yields.lockYields = lockYields;
        yields.circulatingSupply = kvcmCirculatingSupply;
        yields.discountParameter = discountParameter;

        // Calculate total kVCM yield from lock yields
        uint256 kVCMYield = _sumRawLockIssues(lockYields);

        // Compute finalized lambdas (already view)
        IRiskyYieldFacet.FinalizationValues memory tbLambdas =
            IRiskyYieldFacet(address(this)).computeFinalizedLambdas(midnightIndex);
        yields.lambdas = tbLambdas;

        // Compute RY distribution with params
        yields.ryDistribution = _computeRYWithLambda(kVCMYield, discountParameter, tbLambdas);

        // Compute K2Y distribution with params
        yields.k2yDistribution = _computeK2YWithParams(idx, tbLambdas);

        // Get K2 stakers total shares (for update calls)
        yields.k2StakersTotalShares = IRiskyYieldFacet(address(this)).getK2StakersTotalShares();

        // Compute RY LP yields using pre-computed distribution and supply
        yields.kvcmK2LpRyYields = IRiskyYieldFacet(address(this))
            .computeRYForLPsWithSupply(
                config.kvcmK2LPToken, midnightIndex, yields.ryDistribution, kvcmCirculatingSupply
            );
        yields.kvcmQLpRyYields = IRiskyYieldFacet(address(this))
            .computeRYForLPsWithSupply(config.kvcmQLPToken, midnightIndex, yields.ryDistribution, kvcmCirculatingSupply);

        // Compute K2Y LP yields using pre-computed distribution and supply
        yields.aqLpK2Yields = IK2YieldFacet(address(this))
            .computeK2YForAQLPsWithSupply(idx, yields.k2yDistribution, kvcmCirculatingSupply);
        yields.agLpK2Yields = IK2YieldFacet(address(this))
            .computeK2YForAGLPsWithSupply(idx, yields.k2yDistribution, kvcmCirculatingSupply);
        yields.kvcmStakersK2Yields = IK2YieldFacet(address(this))
            .computeK2YForKVCMStakersWithSupply(idx, yields.k2yDistribution, kvcmCirculatingSupply);

        return yields;
    }

    // ---------------------------------------------------------------------
    // Internal: Compute RY With Params (via delegate call)
    // ---------------------------------------------------------------------

    /**
     * @notice Computes RY distribution using passed params via delegate call to RiskyYieldFacet
     */
    function _computeRYWithLambda(
        uint256 kVCMYield,
        uint256 discountParam,
        IRiskyYieldFacet.FinalizationValues memory tbLambdas
    ) internal view returns (IRiskyYieldFacet.RYDistribution memory) {
        return IRiskyYieldFacet(address(this)).computeRYWithLambda(kVCMYield, discountParam, tbLambdas);
    }

    // ---------------------------------------------------------------------
    // Internal: Compute K2Y With Params (via delegate call)
    // ---------------------------------------------------------------------

    /**
     * @notice Computes K2Y distribution using passed lambdas via delegate call to K2YieldFacet
     */
    function _computeK2YWithParams(uint64 midnightIndex, IRiskyYieldFacet.FinalizationValues memory lambdas)
        internal
        view
        returns (IK2YieldFacet.K2YDistribution memory)
    {
        return IK2YieldFacet(address(this)).computeK2YDistributionWithLambdas(midnightIndex, lambdas);
    }

    // ---------------------------------------------------------------------
    // Internal Helpers
    // ---------------------------------------------------------------------

    function _sumRawLockIssues(IRollUpdateFacet.MaturityYields[] memory yields) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < yields.length; i++) {
            total += yields[i].rawLockIssueForInterval;
        }
    }
}
