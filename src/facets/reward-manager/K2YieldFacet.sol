// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {Constants} from "../../libraries/Constants.sol";
import {Errors} from "../../libraries/Errors.sol";
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {IK2YieldFacet} from "../../interfaces/RewardManager/IK2YieldFacet.sol";
import {IK2YieldCurveFacet} from "../../interfaces/RewardManager/IK2YieldCurveFacet.sol";
import {IProtocolRewardsEscrow} from "../../interfaces/IProtocolRewardsEscrow.sol";
import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IRollUpdateFacet} from "../../interfaces/RewardManager/IRollUpdateFacet.sol";
import {IKvcmLPStakingFacet} from "../../interfaces/StakingManager/IKvcmLPStakingFacet.sol";
import {IKvcmStakingFacet} from "../../interfaces/StakingManager/IKvcmStakingFacet.sol";
import {IK2StakingFacet} from "../../interfaces/StakingManager/IK2StakingFacet.sol";
import {IProtocolSupplyOracle} from "../../interfaces/IProtocolSupplyOracle.sol";
import {IRiskyYieldFacet} from "../../interfaces/RewardManager/IRiskyYieldFacet.sol";
import {AeroLPUtilsLib} from "../../libraries/AeroLPUtils.sol";

contract K2YieldFacet is IK2YieldFacet, ReentrancyGuard {
    modifier onlyStateUpdater() {
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();

        (bool hasStateUpdaterRole,) =
            IAccessManager(c.accessManager).hasRole(CarbonSystemRoleLib.REWARDS_MANAGER_STATE_UPDATER, msg.sender);

        if (!hasStateUpdaterRole) {
            revert Errors.NotRewardManagerStateUpdater();
        }

        _;
    }

    modifier onlySystemAdminOrStateUpdater() {
        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();
        IAccessManager accessManager = IAccessManager(c.accessManager);
        (bool hasStateUpdaterRole,) =
            accessManager.hasRole(CarbonSystemRoleLib.REWARDS_MANAGER_STATE_UPDATER, msg.sender);
        (bool hasCarbonSystemAdminRole,) = accessManager.hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (!hasStateUpdaterRole && !hasCarbonSystemAdminRole) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    /**
     * @notice Computes the K2 Yield distribution for a given midnight index.
     * @dev This is a read-only function that can be called at a specific block number.
     * @param midNightIndex The midnight index to compute K2Y for.
     * @return distribution The K2Y distribution across different pools and stakers.
     */
    function computeK2YDistribution(uint64 midNightIndex)
        public
        view
        returns (IK2YieldFacet.K2YDistribution memory distribution)
    {
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout =
            RewardManagerStorage.kvcmLockYieldLayout();

        // K2Y computation depends on KVCM Lock yield data - validate it exists and is settled
        RewardManagerStorage.IntervalData storage intervalData = kvcmLockYieldLayout.intervalData[midNightIndex];

        // Validate KVCM Lock yield has been distributed and settled for this midnight
        if (!intervalData.settled) {
            revert Errors.KVCMYieldIntervalNotSettled(midNightIndex);
        }

        // Get storage references
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.DailyLambdaCache storage dailyLambdaCache = r.dailyLambdaCache[midNightIndex];

        // Verify lambdas are finalized before computing distribution.
        // Day N window = [midnight(N-1), midnight(N)), and it ends at T(N).
        uint256 midNightTimestamp = IMaturityManager(config.maturityManager).getMidnightTimestampForIndex(midNightIndex);

        if (dailyLambdaCache.lastLambdaUpdateTimestamp != midNightTimestamp) {
            revert Errors.LambdasNotFinalized(midNightIndex);
        }

        // it will fetch correct values when read for a particular block.
        uint256 totalK2Staked = _getTotalK2Staked(); // G: Total K2 staked (K2 staked)
        uint256 totalK2InAGPool = _getTotalK2InAGPool(); // L: Total K2 in AG pool
        // S: Total KVCM staked (Klima Lock staked)
        uint256 kvcmStaked = IKvcmStakingFacet(config.stakingManager).getTotalKvcmLocked();

        // Calculate G^2 and L^2. We don't need to use G and L as proportions
        // of circulating supply as they cancel out later in the formula.
        uint256 GSq = Math.mulDiv(totalK2Staked, totalK2Staked, Constants.WAD);
        uint256 LSq = Math.mulDiv(totalK2InAGPool, totalK2InAGPool, Constants.WAD);
        uint256 totalK2Yield = IK2YieldCurveFacet(address(this)).dailyEmission(midNightIndex);

        // relative_utilisation
        uint256 relUtilisation = _calcRelativeUtilisation(totalK2Staked, totalK2InAGPool);
        uint256 absoluteUtilisation = _calcAbsoluteUtilisation(totalK2Staked, totalK2InAGPool);

        // Validate utilisations are within scale
        if (relUtilisation > Constants.WAD || absoluteUtilisation > Constants.WAD) {
            revert Errors.UtilisationExceedsScale(relUtilisation, absoluteUtilisation);
        }

        uint256 utilisation = Math.mulDiv(relUtilisation, absoluteUtilisation, Constants.WAD);
        (uint256 normalizedLambdaGG, uint256 normalizedLambdaG, uint256 normalizedLambdaQ) =
            _normalizeLambdas(dailyLambdaCache.tblambdaGG, dailyLambdaCache.tblambdaG, dailyLambdaCache.tblambdaQ);

        // Calculate and set distributions
        distribution.kvcmK2LP = _calcAGStakersYield(
            CalculateAGYieldParams({
                totalK2Yield: totalK2Yield,
                GSq: GSq,
                LSq: LSq,
                lambdaG: normalizedLambdaG,
                lambdaGG: normalizedLambdaGG,
                utilisation: utilisation
            })
        );
        distribution.kvcmQLP = _calcAQStakersYield(
            CalculateAQYieldParams({
                totalK2Yield: totalK2Yield,
                GSq: GSq,
                LSq: LSq,
                lambdaQ: normalizedLambdaQ,
                lambdaGG: normalizedLambdaGG,
                utilisation: utilisation
            })
        );

        distribution.k2Stakers = 0;
        distribution.kvcmStakers = 0;
        distribution.treasury = 0;

        // K2 Stakers yield: Weight = (CirKVCM - S) × L² / (CirKVCM × (L² + G²))
        // where S is KVCM staked, G is K2 staked, L is K2 in AG pool
        distribution.k2Stakers = _calcK2YforK2Stakers(
            K2YforK2StakersParams({
                totalK2Yield: totalK2Yield,
                kvcmStaked: kvcmStaked, // S: KVCM staked
                L: totalK2InAGPool, // L: K2 in AG pool
                G: totalK2Staked, // G: K2 staked
                utilisation: utilisation
            })
        );

        // KVCM Stakers yield: Weight = S × L² / (CirKVCM × (L² + G²))
        // where S is KVCM staked, G is K2 staked, L is K2 in AG pool
        distribution.kvcmStakers = _calcK2YForKVCMStakers(
            K2YKVCMStakers({
                totalK2Yield: totalK2Yield,
                kvcmStaked: kvcmStaked, // S: KVCM staked
                L: totalK2InAGPool, // L: K2 in AG pool
                G: totalK2Staked, // G: K2 staked
                utilisation: utilisation
            })
        );

        // ---------------------------------------------------------------------
        // Enforce distribution-level invariant:
        //   1) Total staker yield (AG LPs + AQ LPs + K2 stakers + KVCM stakers)
        //      must not exceed totalK2Yield * utilisation (floored).
        //   2) Treasury gets the residual so that:
        //         kvcmK2LP + kvcmQLP + k2Stakers + kvcmStakers + treasury
        //       always equals totalK2Yield (up to integer truncation).
        // ---------------------------------------------------------------------

        uint256 maxStakerYield = Math.mulDiv(totalK2Yield, utilisation, Constants.WAD);

        uint256 stakerSum =
            distribution.kvcmK2LP + distribution.kvcmQLP + distribution.k2Stakers + distribution.kvcmStakers;

        if (stakerSum > maxStakerYield && stakerSum > 0) {
            uint256 scale = Math.mulDiv(maxStakerYield, Constants.WAD, stakerSum);

            // Scale each staker bucket proportionally
            distribution.kvcmK2LP = Math.mulDiv(distribution.kvcmK2LP, scale, Constants.WAD);
            distribution.kvcmQLP = Math.mulDiv(distribution.kvcmQLP, scale, Constants.WAD);
            distribution.k2Stakers = Math.mulDiv(distribution.k2Stakers, scale, Constants.WAD);

            // Use kvcmStakers as residual to avoid cumulative rounding drift
            uint256 partialStakerSum = distribution.kvcmK2LP + distribution.kvcmQLP + distribution.k2Stakers;
            distribution.kvcmStakers = maxStakerYield > partialStakerSum ? maxStakerYield - partialStakerSum : 0;
        }

        uint256 newStakerSum =
            distribution.kvcmK2LP + distribution.kvcmQLP + distribution.k2Stakers + distribution.kvcmStakers;

        if (newStakerSum >= totalK2Yield) {
            // In extreme rounding cases, treasury gets nothing
            distribution.treasury = 0;
        } else {
            distribution.treasury = totalK2Yield - newStakerSum;
        }

        return distribution;
    }

    /**
     * @notice Computes K2Y distribution using passed lambdas (for BatchComputeFacet)
     * @dev Skips lambda finalization and settlement validation - caller must ensure lambdas are valid
     * @param midNightIndex The midnight index
     * @param lambdas Pre-computed finalization values
     * @return distribution The K2Y distribution
     */
    function computeK2YDistributionWithLambdas(uint64 midNightIndex, IRiskyYieldFacet.FinalizationValues memory lambdas)
        public
        view
        returns (IK2YieldFacet.K2YDistribution memory distribution)
    {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        // Read current state (these don't depend on prior writes)
        uint256 totalK2Staked = _getTotalK2Staked(); // G
        uint256 totalK2InAGPool = _getTotalK2InAGPool(); // L
        uint256 kvcmStaked = IKvcmStakingFacet(config.stakingManager).getTotalKvcmLocked(); // S

        uint256 GSq = Math.mulDiv(totalK2Staked, totalK2Staked, Constants.WAD);
        uint256 LSq = Math.mulDiv(totalK2InAGPool, totalK2InAGPool, Constants.WAD);
        uint256 totalK2Yield = IK2YieldCurveFacet(address(this)).dailyEmission(midNightIndex);

        // Calculate utilisation
        uint256 relUtilisation = _calcRelativeUtilisation(totalK2Staked, totalK2InAGPool);
        uint256 absoluteUtilisation = _calcAbsoluteUtilisation(totalK2Staked, totalK2InAGPool);

        if (relUtilisation > Constants.WAD || absoluteUtilisation > Constants.WAD) {
            revert Errors.UtilisationExceedsScale(relUtilisation, absoluteUtilisation);
        }

        uint256 utilisation = Math.mulDiv(relUtilisation, absoluteUtilisation, Constants.WAD);
        (uint256 normalizedLambdaGG, uint256 normalizedLambdaG, uint256 normalizedLambdaQ) =
            _normalizeLambdas(lambdas.finalGG, lambdas.finalG, lambdas.finalQ);

        // Calculate distributions using passed lambdas
        distribution.kvcmK2LP = _calcAGStakersYield(
            CalculateAGYieldParams({
                totalK2Yield: totalK2Yield,
                GSq: GSq,
                LSq: LSq,
                lambdaG: normalizedLambdaG,
                lambdaGG: normalizedLambdaGG,
                utilisation: utilisation
            })
        );
        distribution.kvcmQLP = _calcAQStakersYield(
            CalculateAQYieldParams({
                totalK2Yield: totalK2Yield,
                GSq: GSq,
                LSq: LSq,
                lambdaQ: normalizedLambdaQ,
                lambdaGG: normalizedLambdaGG,
                utilisation: utilisation
            })
        );
        distribution.k2Stakers = _calcK2YforK2Stakers(
            K2YforK2StakersParams({
                totalK2Yield: totalK2Yield,
                kvcmStaked: kvcmStaked,
                L: totalK2InAGPool,
                G: totalK2Staked,
                utilisation: utilisation
            })
        );
        distribution.kvcmStakers = _calcK2YForKVCMStakers(
            K2YKVCMStakers({
                totalK2Yield: totalK2Yield,
                kvcmStaked: kvcmStaked,
                L: totalK2InAGPool,
                G: totalK2Staked,
                utilisation: utilisation
            })
        );

        // Enforce distribution invariant
        uint256 maxStakerYield = Math.mulDiv(totalK2Yield, utilisation, Constants.WAD);
        uint256 stakerSum =
            distribution.kvcmK2LP + distribution.kvcmQLP + distribution.k2Stakers + distribution.kvcmStakers;

        if (stakerSum > maxStakerYield && stakerSum > 0) {
            uint256 scale = Math.mulDiv(maxStakerYield, Constants.WAD, stakerSum);
            distribution.kvcmK2LP = Math.mulDiv(distribution.kvcmK2LP, scale, Constants.WAD);
            distribution.kvcmQLP = Math.mulDiv(distribution.kvcmQLP, scale, Constants.WAD);
            distribution.k2Stakers = Math.mulDiv(distribution.k2Stakers, scale, Constants.WAD);

            uint256 partialStakerSum = distribution.kvcmK2LP + distribution.kvcmQLP + distribution.k2Stakers;
            distribution.kvcmStakers = maxStakerYield > partialStakerSum ? maxStakerYield - partialStakerSum : 0;
        }

        uint256 newStakerSum =
            distribution.kvcmK2LP + distribution.kvcmQLP + distribution.k2Stakers + distribution.kvcmStakers;
        distribution.treasury = newStakerSum >= totalK2Yield ? 0 : totalK2Yield - newStakerSum;
    }

    function computeK2YForAQLPs(uint64 midNightIndex)
        public
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 totalK2YieldForLP = computeK2YDistribution(midNightIndex).kvcmQLP;
        if (totalK2YieldForLP == 0) {
            return yields;
        }
        return _computeK2YForLPs(config.kvcmQLPToken, midNightIndex, totalK2YieldForLP);
    }

    function computeK2YForAGLPs(uint64 midNightIndex)
        public
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 totalK2YieldForLP = computeK2YDistribution(midNightIndex).kvcmK2LP;
        if (totalK2YieldForLP == 0) {
            return yields;
        }
        return _computeK2YForLPs(config.kvcmK2LPToken, midNightIndex, totalK2YieldForLP);
    }

    function computeK2YDistributionForKVCMStakers(uint64 midNightIndex)
        public
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        uint256 totalK2YieldForKVCM = computeK2YDistribution(midNightIndex).kvcmStakers;
        if (totalK2YieldForKVCM == 0) {
            return yields;
        }
        return _calcDistributionForKVCMStakers(midNightIndex, totalK2YieldForKVCM);
    }

    /**
     * @notice Compute K2Y for AQ LPs using a pre-computed distribution (for BatchComputeFacet)
     */
    function computeK2YForAQLPsWithDistribution(uint64 midNightIndex, IK2YieldFacet.K2YDistribution memory distribution)
        public
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 totalK2YieldForLP = distribution.kvcmQLP;
        if (totalK2YieldForLP == 0) {
            return yields;
        }
        return _computeK2YForLPs(config.kvcmQLPToken, midNightIndex, totalK2YieldForLP);
    }

    /**
     * @notice Compute K2Y for AG LPs using a pre-computed distribution (for BatchComputeFacet)
     */
    function computeK2YForAGLPsWithDistribution(uint64 midNightIndex, IK2YieldFacet.K2YDistribution memory distribution)
        public
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 totalK2YieldForLP = distribution.kvcmK2LP;
        if (totalK2YieldForLP == 0) {
            return yields;
        }
        return _computeK2YForLPs(config.kvcmK2LPToken, midNightIndex, totalK2YieldForLP);
    }

    /**
     * @notice Compute K2Y for KVCM stakers using a pre-computed distribution (for BatchComputeFacet)
     */
    function computeK2YForKVCMStakersWithDistribution(
        uint64 midNightIndex,
        IK2YieldFacet.K2YDistribution memory distribution
    ) public view returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields) {
        uint256 totalK2YieldForKVCM = distribution.kvcmStakers;
        if (totalK2YieldForKVCM == 0) {
            return yields;
        }
        return _calcDistributionForKVCMStakers(midNightIndex, totalK2YieldForKVCM);
    }

    /**
     * @notice Compute K2Y for AQ LPs using distribution and circulatingSupply (for BatchComputeFacet)
     */
    function computeK2YForAQLPsWithSupply(
        uint64 midNightIndex,
        IK2YieldFacet.K2YDistribution memory distribution,
        uint256 circulatingSupply
    ) public view returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields) {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 totalK2YieldForLP = distribution.kvcmQLP;
        if (totalK2YieldForLP == 0) {
            return yields;
        }
        return _computeK2YForLPsWithSupply(config.kvcmQLPToken, midNightIndex, totalK2YieldForLP, circulatingSupply);
    }

    /**
     * @notice Compute K2Y for AG LPs using distribution and circulatingSupply (for BatchComputeFacet)
     */
    function computeK2YForAGLPsWithSupply(
        uint64 midNightIndex,
        IK2YieldFacet.K2YDistribution memory distribution,
        uint256 circulatingSupply
    ) public view returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields) {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 totalK2YieldForLP = distribution.kvcmK2LP;
        if (totalK2YieldForLP == 0) {
            return yields;
        }
        return _computeK2YForLPsWithSupply(config.kvcmK2LPToken, midNightIndex, totalK2YieldForLP, circulatingSupply);
    }

    /**
     * @notice Compute K2Y for KVCM stakers using distribution and circulatingSupply (for BatchComputeFacet)
     */
    function computeK2YForKVCMStakersWithSupply(
        uint64 midNightIndex,
        IK2YieldFacet.K2YDistribution memory distribution,
        uint256 circulatingSupply
    ) public view returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields) {
        uint256 totalK2YieldForKVCM = distribution.kvcmStakers;
        if (totalK2YieldForKVCM == 0) {
            return yields;
        }
        return _calcDistributionForKVCMStakersWithSupply(midNightIndex, totalK2YieldForKVCM, circulatingSupply);
    }

    function updateK2YAccForLPs(
        address lpToken,
        uint64 midNightIndex,
        IK2YieldFacet.MaturityYieldWithShares[] calldata maturityYields
    ) external onlyStateUpdater nonReentrant {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }

        // Validate inputs
        if (lpToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Validate that Klima Lock yield has been distributed and settled for this midnight
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout =
            RewardManagerStorage.kvcmLockYieldLayout();

        // Validate sequential processing and prevent double spending for LP K2Yield (per LP token)
        RewardManagerStorage.K2YieldLayout storage k2YieldLayout = RewardManagerStorage.k2YieldLayout();
        uint128 lastProcessed = k2YieldLayout.lastProcessedMidnightIndexPerLP[lpToken];

        _validateNoFutureSettlement(midNightIndex);
        _validateSequentialProcessing(midNightIndex, SafeCast.toUint64(lastProcessed));
        _validateKVCMYieldSettlement(midNightIndex, kvcmLockYieldLayout);

        // Empty array: zero yield for this LP. Advance index and return.
        if (maturityYields.length == 0) {
            k2YieldLayout.lastProcessedMidnightIndexPerLP[lpToken] = SafeCast.toUint128(midNightIndex);
            return;
        }

        _validateMaturityYieldsArray(maturityYields);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        uint256 totalRewardsDistributed;

        // Process each maturity
        for (uint256 i = 0; i < maturityYields.length; i++) {
            // Cache struct fields to avoid repeated calldata reads
            IK2YieldFacet.MaturityYieldWithShares calldata maturityYield = maturityYields[i];
            uint256 maturityId = maturityYield.maturityId;
            uint256 yieldAmount = maturityYield.k2Yield;
            uint256 totalShares = maturityYield.totalShares; // From parameter (midnight value)

            // Skip if no shares (consistency check)
            if (totalShares == 0) continue;

            RewardManagerStorage.GlobalRewardsState storage lpK2YieldGlobal = r.lpK2YieldGlobal[lpToken][maturityId];

            // ALWAYS update lastKeeperUpdate and snapshot (even for zero yield)
            // This ensures sequential processing works correctly
            lpK2YieldGlobal.lastKeeperUpdate = midNightIndex;

            // Update daily snapshot for this maturity
            RewardManagerStorage.AccumulatorSnapshot storage snapshot =
                r.lpK2YieldAccSnapshot[lpToken][maturityId][midNightIndex];
            snapshot.midnightAccumulator = lpK2YieldGlobal.globalAccumulator;

            // Only update accumulator and rewards if yield > 0
            if (yieldAmount > 0) {
                uint256 deltaAccumulator = Math.mulDiv(yieldAmount, Constants.WAD, totalShares);

                // Update global accumulator
                lpK2YieldGlobal.globalAccumulator += deltaAccumulator;
                lpK2YieldGlobal.totalRewards += yieldAmount;

                // Re-update snapshot with new accumulator
                snapshot.midnightAccumulator = lpK2YieldGlobal.globalAccumulator;

                totalRewardsDistributed += yieldAmount;

                emit LPK2YieldAccumulatorUpdated(
                    lpToken, midNightIndex, maturityId, yieldAmount, lpK2YieldGlobal.globalAccumulator
                );
            }
        }

        // Update the last processed midnight index for this LP token to prevent reprocessing
        k2YieldLayout.lastProcessedMidnightIndexPerLP[lpToken] = SafeCast.toUint128(midNightIndex);

        // Safeguard: Total distributed yield cannot exceed daily emission
        uint256 maxEmission = IK2YieldCurveFacet(address(this)).dailyEmission(midNightIndex);
        if (totalRewardsDistributed > maxEmission) {
            revert Errors.YieldExceedsDailyEmission(totalRewardsDistributed, maxEmission);
        }

        // Transfer K2 rewards from escrow to rewards manager

        if (totalRewardsDistributed > 0) {
            _transferK2FromEscrow(totalRewardsDistributed);
        }
    }

    function updateK2YAccForKVCMStakers(uint64 midNightIndex, IK2YieldFacet.MaturityYieldWithShares[] memory yields)
        external
        onlyStateUpdater
        nonReentrant
    {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }

        // Validate that KVCM Lock yield has been distributed and settled for this midnight
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout =
            RewardManagerStorage.kvcmLockYieldLayout();

        // Validate sequential processing and prevent double spending for KVCM K2Yield
        RewardManagerStorage.K2YieldLayout storage k2YieldLayout = RewardManagerStorage.k2YieldLayout();
        uint64 lastProcessed = k2YieldLayout.lastProcessedMidnightIndexKVCM;

        _validateNoFutureSettlement(midNightIndex);
        _validateSequentialProcessing(midNightIndex, lastProcessed);
        _validateKVCMYieldSettlement(midNightIndex, kvcmLockYieldLayout);

        // Empty array: zero yield for KVCM stakers. Advance index and return.
        if (yields.length == 0) {
            k2YieldLayout.lastProcessedMidnightIndexKVCM = SafeCast.toUint64(midNightIndex);
            return;
        }

        _validateMaturityYieldsArray(yields);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        uint256 totalRewardsDistributed;

        // Process each maturity
        for (uint256 i = 0; i < yields.length; i++) {
            // Cache struct fields to avoid repeated memory reads
            IK2YieldFacet.MaturityYieldWithShares memory maturityYield = yields[i];
            uint256 maturityId = maturityYield.maturityId;
            uint256 yieldAmount = maturityYield.k2Yield;
            uint256 totalShares = maturityYield.totalShares; // From parameter (midnight value)

            // Skip if no shares (consistency check)
            if (totalShares == 0) continue;

            RewardManagerStorage.GlobalRewardsState storage kvcmK2YieldGlobal = r.kvcmK2YieldGlobal[maturityId];

            // ALWAYS update lastKeeperUpdate and snapshot (even for zero yield)
            // This ensures sequential processing works correctly
            kvcmK2YieldGlobal.lastKeeperUpdate = midNightIndex;

            // Update daily snapshot for this maturity
            RewardManagerStorage.AccumulatorSnapshot storage snapshot =
                r.kvcmK2YieldAccSnapshot[maturityId][midNightIndex];
            snapshot.midnightAccumulator = kvcmK2YieldGlobal.globalAccumulator;

            // Only update accumulator and rewards if yield > 0
            if (yieldAmount > 0) {
                uint256 deltaAccumulator = Math.mulDiv(yieldAmount, Constants.WAD, totalShares);

                // Update global accumulator
                kvcmK2YieldGlobal.globalAccumulator += deltaAccumulator;
                kvcmK2YieldGlobal.totalRewards += yieldAmount;

                // Re-update snapshot with new accumulator
                snapshot.midnightAccumulator = kvcmK2YieldGlobal.globalAccumulator;

                totalRewardsDistributed += yieldAmount;

                emit KVCMK2YieldAccumulatorUpdated(
                    midNightIndex, maturityId, yieldAmount, kvcmK2YieldGlobal.globalAccumulator
                );
            }
        }

        // Update the last processed midnight index for KVCM stakers to prevent reprocessing
        k2YieldLayout.lastProcessedMidnightIndexKVCM = SafeCast.toUint64(midNightIndex);

        // Safeguard: Total distributed yield cannot exceed daily emission
        uint256 maxEmission = IK2YieldCurveFacet(address(this)).dailyEmission(midNightIndex);
        if (totalRewardsDistributed > maxEmission) {
            revert Errors.YieldExceedsDailyEmission(totalRewardsDistributed, maxEmission);
        }

        // Transfer K2 rewards from escrow to rewards manager

        if (totalRewardsDistributed > 0) {
            _transferK2FromEscrow(totalRewardsDistributed);
        }
    }

    /**
     * @notice Updates the accumulator for K2 stakers using pre-computed totalShares
     * @dev Takes totalShares as parameter - no state reads from current block
     * @param midNightIndex The midnight index.
     * @param totalK2YieldForK2Stakers The rewards amount from computeK2YDistribution.
     * @param totalShares The total shares captured at midnight block.
     */
    function updateK2YAccForK2Stakers(uint64 midNightIndex, uint256 totalK2YieldForK2Stakers, uint256 totalShares)
        external
        onlyStateUpdater
        nonReentrant
    {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }

        // Safeguard: totalShares cannot exceed K2 supply
        // This catches parameter swap errors (yield passed as shares would be >> K2 supply)
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        uint256 k2Supply = IERC20(config.k2Token).totalSupply();
        if (totalShares > k2Supply) {
            revert Errors.TotalSharesExceedsK2Supply(totalShares, k2Supply);
        }

        // Safeguard: yield cannot exceed daily emission limit
        // This ensures that we don't distribute more than the curve allows for a given day
        uint256 maxEmission = IK2YieldCurveFacet(address(this)).dailyEmission(midNightIndex);
        if (totalK2YieldForK2Stakers > maxEmission) {
            revert Errors.YieldExceedsDailyEmission(totalK2YieldForK2Stakers, maxEmission);
        }

        // Safeguard: yield cannot exceed escrowed K2 balance
        // This catches parameter swap errors and unreasonably high yield values
        uint256 escrowedK2 = IProtocolRewardsEscrow(config.protocolRewardsEscrow).getEscrowBalance().k2RewardsEscrowed;
        if (totalK2YieldForK2Stakers > escrowedK2) {
            revert Errors.YieldExceedsEscrowBalance(totalK2YieldForK2Stakers, escrowedK2);
        }

        // Validate that KVCM Lock yield has been distributed and settled for this midnight
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout =
            RewardManagerStorage.kvcmLockYieldLayout();

        // Validate sequential processing and prevent double spending for K2 Stakers K2Yield
        RewardManagerStorage.K2YieldLayout storage k2YieldLayout = RewardManagerStorage.k2YieldLayout();
        uint64 lastProcessed = k2YieldLayout.lastProcessedMidnightIndexK2Stakers;

        _validateNoFutureSettlement(midNightIndex);
        _validateSequentialProcessing(midNightIndex, lastProcessed);
        _validateKVCMYieldSettlement(midNightIndex, kvcmLockYieldLayout);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.GlobalRewardsState storage k2StakersK2YieldGlobal = r.k2StakersK2YieldGlobal;

        // ALWAYS update lastKeeperUpdate and snapshot (even for zero rewards)
        // This ensures sequential processing works correctly
        k2StakersK2YieldGlobal.lastKeeperUpdate = midNightIndex;

        // Update daily snapshot
        RewardManagerStorage.AccumulatorSnapshot storage snapshot = r.k2K2YieldAccSnapshot[midNightIndex];
        snapshot.midnightAccumulator = k2StakersK2YieldGlobal.globalAccumulator;

        // No stakers: allow zero-reward checkpointing so midnight index can progress.
        if (totalShares == 0) {
            // Update the last processed midnight index for K2 Stakers K2Yield to prevent reprocessing
            k2YieldLayout.lastProcessedMidnightIndexK2Stakers = SafeCast.toUint64(midNightIndex);
            emit K2StakersK2YieldAccumulatorUpdated(midNightIndex, 0, k2StakersK2YieldGlobal.globalAccumulator);
            return;
        }

        // Only update accumulator and rewards if totalK2YieldForK2Stakers > 0
        if (totalK2YieldForK2Stakers > 0) {
            // USE totalShares FROM PARAMETER (midnight value) instead of reading from storage
            uint256 deltaAccumulator = Math.mulDiv(totalK2YieldForK2Stakers, Constants.WAD, totalShares);

            // Update global accumulator
            k2StakersK2YieldGlobal.globalAccumulator += deltaAccumulator;
            k2StakersK2YieldGlobal.totalRewards += totalK2YieldForK2Stakers;

            // Re-update snapshot with new accumulator
            snapshot.midnightAccumulator = k2StakersK2YieldGlobal.globalAccumulator;
        }

        // Update the last processed midnight index for K2 Stakers K2Yield to prevent reprocessing
        k2YieldLayout.lastProcessedMidnightIndexK2Stakers = SafeCast.toUint64(midNightIndex);

        emit K2StakersK2YieldAccumulatorUpdated(
            midNightIndex, totalK2YieldForK2Stakers, k2StakersK2YieldGlobal.globalAccumulator
        );

        if (totalK2YieldForK2Stakers > 0) {
            // Transfer K2 rewards from escrow to rewards manager (last operation)
            _transferK2FromEscrow(totalK2YieldForK2Stakers);
        }
    }

    /**
     * @notice Distributes K2 Yield to the treasury.
     * @dev Validates sequential processing and transfers K2Y from the escrow contract.
     * @param midNightIndex The midnight index for which yield is distributed.
     * @param totalK2YieldForTreasury The amount of K2Y to be distributed.
     */
    function distributeK2YToTreasury(uint64 midNightIndex, uint256 totalK2YieldForTreasury)
        external
        onlyStateUpdater
        nonReentrant
    {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }

        // Validate that KVCM Lock yield has been distributed and settled for this midnight
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout =
            RewardManagerStorage.kvcmLockYieldLayout();

        RewardManagerStorage.K2YieldLayout storage k2YieldLayout = RewardManagerStorage.k2YieldLayout();
        uint64 lastProcessed = k2YieldLayout.lastProcessedMidnightIndexTreasury;

        _validateNoFutureSettlement(midNightIndex);
        _validateSequentialProcessing(midNightIndex, lastProcessed);
        _validateKVCMYieldSettlement(midNightIndex, kvcmLockYieldLayout);

        // Update state before external calls
        k2YieldLayout.lastProcessedMidnightIndexTreasury = SafeCast.toUint64(midNightIndex);

        // Safeguard: Treasury yield cannot exceed daily emission
        uint256 maxEmission = IK2YieldCurveFacet(address(this)).dailyEmission(midNightIndex);
        if (totalK2YieldForTreasury > maxEmission) {
            revert Errors.YieldExceedsDailyEmission(totalK2YieldForTreasury, maxEmission);
        }

        emit K2YieldDistributedToTreasury(midNightIndex, totalK2YieldForTreasury);

        // Transfer K2Y from escrow to treasury
        if (totalK2YieldForTreasury > 0) {
            RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
            IProtocolRewardsEscrow(config.protocolRewardsEscrow).transferK2ToTreasury(totalK2YieldForTreasury);
        }
    }

    function getK2YieldLastProcessedIndices(address k2LP, address qLP)
        external
        view
        returns (IK2YieldFacet.K2YieldProcessedIndices memory)
    {
        RewardManagerStorage.K2YieldLayout storage k2YieldLayout = RewardManagerStorage.k2YieldLayout();
        return IK2YieldFacet.K2YieldProcessedIndices({
            lastProcessedMidnightIndexKVCM: SafeCast.toUint128(k2YieldLayout.lastProcessedMidnightIndexKVCM),
            lastProcessedMidnightIndexK2Stakers: SafeCast.toUint128(k2YieldLayout.lastProcessedMidnightIndexK2Stakers),
            lastProcessedMidnightIndexTreasury: SafeCast.toUint128(k2YieldLayout.lastProcessedMidnightIndexTreasury),
            lastProcessedMidnightIndexK2LP: k2YieldLayout.lastProcessedMidnightIndexPerLP[k2LP],
            lastProcessedMidnightIndexQLP: k2YieldLayout.lastProcessedMidnightIndexPerLP[qLP]
        });
    }

    /* ======================================
     * INTERNAL HELPERS
     * ======================================
     */

    // K2Y weight formulas expect lambdas as plain proportions that sum to LAMBDA_SCALE.
    function _normalizeLambdas(uint256 tbLambdaGG, uint256 tbLambdaG, uint256 tbLambdaQ)
        internal
        pure
        returns (uint256 normalizedLambdaGG, uint256 normalizedLambdaG, uint256 normalizedLambdaQ)
    {
        uint256 totalLambda = tbLambdaGG + tbLambdaG + tbLambdaQ;
        if (totalLambda == 0) {
            return (0, 0, 0);
        }

        normalizedLambdaGG = Math.mulDiv(tbLambdaGG, Constants.LAMBDA_SCALE, totalLambda);
        normalizedLambdaG = Math.mulDiv(tbLambdaG, Constants.LAMBDA_SCALE, totalLambda);
        normalizedLambdaQ = Constants.LAMBDA_SCALE - normalizedLambdaGG - normalizedLambdaG;
    }

    // weight = (lambdaG * GSq) / ((LAMBDA_SCALE - lambdaGG) * (GSq + LSq))
    // result = totalK2Yield * utilisation * weight
    function _calcAGStakersYield(CalculateAGYieldParams memory params) internal pure returns (uint256) {
        if (params.totalK2Yield == 0) return 0;
        if (params.utilisation == 0) return 0;

        uint256 numeratorTerm = Math.mulDiv(params.lambdaG, params.GSq, Constants.LAMBDA_SCALE);
        uint256 denominatorTerm =
            Math.mulDiv((Constants.LAMBDA_SCALE - params.lambdaGG), (params.GSq + params.LSq), Constants.LAMBDA_SCALE);

        if (denominatorTerm == 0) {
            return 0;
        }

        uint256 weight = Math.mulDiv(numeratorTerm, Constants.WAD, denominatorTerm);
        uint256 baseYield = Math.mulDiv(params.totalK2Yield, params.utilisation, Constants.WAD);

        return Math.mulDiv(baseYield, weight, Constants.WAD);
    }

    // weight = (lambdaQ * GSq) / ((LAMBDA_SCALE - lambdaGG) * (GSq + LSq))
    // result = totalK2Yield * utilisation * weight
    function _calcAQStakersYield(CalculateAQYieldParams memory params) internal pure returns (uint256) {
        if (params.totalK2Yield == 0) return 0;
        if (params.utilisation == 0) return 0;

        uint256 numeratorTerm = Math.mulDiv(params.lambdaQ, params.GSq, Constants.LAMBDA_SCALE);
        uint256 denominatorTerm =
            Math.mulDiv((Constants.LAMBDA_SCALE - params.lambdaGG), (params.GSq + params.LSq), Constants.LAMBDA_SCALE);

        if (denominatorTerm == 0) {
            return 0;
        }

        uint256 weight = Math.mulDiv(numeratorTerm, Constants.WAD, denominatorTerm);
        return Math.mulDiv(Math.mulDiv(params.totalK2Yield, params.utilisation, Constants.WAD), weight, Constants.WAD);
    }

    function _getLatestTokensSupply() internal view returns (uint256, uint256) {
        uint256 latestKvcmSupply =
            IProtocolSupplyOracle(RewardManagerStorage.configLayout().protocolSupplyOracle).getKvcmSupply();

        uint256 latestK2Supply =
            IProtocolSupplyOracle(RewardManagerStorage.configLayout().protocolSupplyOracle).getK2Supply();

        if (latestKvcmSupply == 0) {
            revert Errors.KVCMCirculatingSupplyIsZero();
        }

        if (latestK2Supply == 0) {
            revert Errors.K2CirculatingSupplyIsZero();
        }

        return (latestK2Supply, latestKvcmSupply);
    }

    function _getTotalK2InAGPool() internal view returns (uint256) {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        if (config.stakingManager == address(0)) {
            revert Errors.InvalidStakingManagerAddress();
        }

        uint256 k2Reserve = AeroLPUtilsLib.getK2ReserveInLp(config.kvcmK2LPToken, config.k2Token);
        return k2Reserve;
    }

    function _getTotalK2Staked() internal view returns (uint256) {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        return IK2StakingFacet(config.stakingManager).getTotalK2Staked();
    }

    function _calcDistributionForKVCMStakers(uint64 midNightIndex, uint256 totalK2YieldForKVCM)
        internal
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        if (totalK2YieldForKVCM == 0) {
            return yields;
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        if (config.stakingManager == address(0)) {
            revert Errors.InvalidStakingManagerAddress();
        }

        address maturityManager = config.maturityManager;
        if (maturityManager == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        uint256 referenceTimestamp = IMaturityManager(maturityManager).getMidnightTimestampForIndex(midNightIndex);

        // Get yield curve values for this midnight index
        (IRollUpdateFacet.YieldCurvePoint[] memory yieldCurveValues,,,) =
            IRollUpdateFacet(address(this)).getFullCurveValuesForInterval(midNightIndex, referenceTimestamp);

        uint256 curveLen = yieldCurveValues.length;

        // Validate yield curve exists
        if (curveLen == 0) {
            revert Errors.NoActiveYieldCurve(midNightIndex);
        }

        // Get storage reference for reading shares
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        // Calculate weights for each maturity
        uint256 denom;
        Weight[40] memory cache;
        uint256 cacheCount = 0;

        for (uint256 idx = 0; idx < curveLen; idx++) {
            if (cacheCount >= 40) break;

            uint256 maturityId = yieldCurveValues[idx].maturityId;
            uint256 kvcmTotalStaked =
                IKvcmStakingFacet(config.stakingManager).getKvcmLockedForMaturity(SafeCast.toUint128(maturityId));

            if (kvcmTotalStaked == 0) continue;

            // Calculate weight: kvcmTotalStaked * zeroCouponYield
            uint256 w = Math.mulDiv(kvcmTotalStaked, yieldCurveValues[idx].zeroCouponYieldCurve, Constants.WAD);

            cache[cacheCount] = Weight({maturityId: maturityId, weight: w});
            denom += w;
            cacheCount++;
        }

        // If no KVCM stakes or all yield weights zero (initial conditions), return empty yields
        if (cacheCount == 0 || denom == 0) {
            return yields;
        }

        // Initialize result arrays
        yields = new IK2YieldFacet.MaturityYieldWithShares[](cacheCount);

        // Calculate yield for each maturity and capture totalShares at midnight block
        for (uint256 j = 0; j < cacheCount; j++) {
            uint256 maturityWeight = Math.mulDiv(cache[j].weight, Constants.WAD, denom);
            uint256 yieldForMaturity = Math.mulDiv(totalK2YieldForKVCM, maturityWeight, Constants.WAD);

            // Capture totalShares at midnight block
            uint256 totalShares = r.kvcmK2YieldGlobal[cache[j].maturityId].totalShares;

            yields[j] = IK2YieldFacet.MaturityYieldWithShares({
                maturityId: cache[j].maturityId, k2Yield: yieldForMaturity, totalShares: totalShares
            });
        }

        return yields;
    }

    function _calcRelativeUtilisation(uint256 G, uint256 L) internal pure returns (uint256) {
        if (G + L == 0) return 0;

        uint256 GSq = Math.mulDiv(G, G, Constants.WAD);
        uint256 LSq = Math.mulDiv(L, L, Constants.WAD);

        uint256 numTerm = 2 * Math.mulDiv(G, L, Constants.WAD);
        uint256 num = Math.mulDiv(numTerm, numTerm, Constants.WAD);

        uint256 denomTerm = GSq + LSq;
        uint256 denom = Math.mulDiv(denomTerm, denomTerm, Constants.WAD);

        if (denom == 0) {
            return 0;
        }

        return Math.mulDiv(num, Constants.WAD, denom);
    }

    // This function will calc total k2 yield for all stakers for an lp token and then distribute it for each maturity ID
    function _computeK2YForLPs(address lpToken, uint64 midNightIndex, uint256 totalK2YieldForLP)
        internal
        view
        returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields)
    {
        if (lpToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (totalK2YieldForLP == 0) {
            return yields;
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        if (config.stakingManager == address(0)) {
            revert Errors.InvalidStakingManagerAddress();
        }

        address maturityManager = config.maturityManager;
        if (maturityManager == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        uint256 referenceTimestamp = IMaturityManager(maturityManager).getMidnightTimestampForIndex(midNightIndex);

        // Get yield curve values for this midnight index
        (IRollUpdateFacet.YieldCurvePoint[] memory yieldCurveValues,,,) =
            IRollUpdateFacet(address(this)).getFullCurveValuesForInterval(midNightIndex, referenceTimestamp);

        uint256 curveLen = yieldCurveValues.length;

        // Validate yield curve exists
        if (curveLen == 0) {
            revert Errors.NoActiveYieldCurve(midNightIndex);
        }

        // Get storage reference for reading shares
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        // Calculate weights for each maturity
        uint256 denom;
        Weight[40] memory cache;
        uint256 cacheCount = 0;

        for (uint256 idx = 0; idx < curveLen; idx++) {
            if (cacheCount >= 40) break;

            uint256 maturityId = yieldCurveValues[idx].maturityId;
            uint256 lpTotalStakes = IKvcmLPStakingFacet(config.stakingManager).getTotalLPStaked(lpToken, maturityId);

            if (lpTotalStakes == 0) continue;

            // Calculate weight: discountFactor * zeroCouponYield * lpTotalStakes
            uint256 w = Math.mulDiv(
                yieldCurveValues[idx].discountFactor, yieldCurveValues[idx].zeroCouponYieldCurve, Constants.WAD
            );
            w = Math.mulDiv(w, lpTotalStakes, Constants.WAD);

            cache[cacheCount] = Weight({maturityId: maturityId, weight: w});
            denom += w;
            cacheCount++;
        }

        // If stakes exist but all yield weights are zero (e.g. midnight index 1
        // where zeroCouponYield hasn't been set yet), return empty yields
        if (denom == 0 || cacheCount == 0) {
            return yields;
        }

        // Initialize result arrays
        yields = new IK2YieldFacet.MaturityYieldWithShares[](cacheCount);

        // Calculate yield for each maturity and capture totalShares at this moment
        for (uint256 j = 0; j < cacheCount; j++) {
            uint256 maturityWeight = Math.mulDiv(cache[j].weight, Constants.WAD, denom);
            uint256 yieldForMaturity = Math.mulDiv(totalK2YieldForLP, maturityWeight, Constants.WAD);

            // Capture totalShares at midnight block
            uint256 totalShares = r.lpK2YieldGlobal[lpToken][cache[j].maturityId].totalShares;

            yields[j] = IK2YieldFacet.MaturityYieldWithShares({
                maturityId: cache[j].maturityId, k2Yield: yieldForMaturity, totalShares: totalShares
            });
        }

        return yields;
    }

    /**
     * @notice Internal helper: compute K2Y for LPs using pre-computed circulatingSupply
     */
    function _computeK2YForLPsWithSupply(
        address lpToken,
        uint64 midNightIndex,
        uint256 totalK2YieldForLP,
        uint256 circulatingSupply
    ) internal view returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields) {
        if (lpToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (totalK2YieldForLP == 0) {
            return yields;
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        if (config.stakingManager == address(0)) {
            revert Errors.InvalidStakingManagerAddress();
        }

        address maturityManager = config.maturityManager;
        if (maturityManager == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        uint256 referenceTimestamp = IMaturityManager(maturityManager).getMidnightTimestampForIndex(midNightIndex);

        // Use the version that accepts circulatingSupply
        (IRollUpdateFacet.YieldCurvePoint[] memory yieldCurveValues,,,) = IRollUpdateFacet(address(this))
            .getFullCurveValuesForIntervalWithSupply(midNightIndex, referenceTimestamp, circulatingSupply);

        uint256 curveLen = yieldCurveValues.length;

        if (curveLen == 0) {
            revert Errors.NoActiveYieldCurve(midNightIndex);
        }

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        uint256 denom;
        Weight[40] memory cache;
        uint256 cacheCount = 0;

        for (uint256 idx = 0; idx < curveLen; idx++) {
            if (cacheCount >= 40) break;

            uint256 maturityId = yieldCurveValues[idx].maturityId;
            uint256 lpTotalStakes = IKvcmLPStakingFacet(config.stakingManager).getTotalLPStaked(lpToken, maturityId);

            if (lpTotalStakes == 0) continue;

            uint256 w = Math.mulDiv(
                yieldCurveValues[idx].discountFactor, yieldCurveValues[idx].zeroCouponYieldCurve, Constants.WAD
            );
            w = Math.mulDiv(w, lpTotalStakes, Constants.WAD);

            cache[cacheCount] = Weight({maturityId: maturityId, weight: w});
            denom += w;
            cacheCount++;
        }

        // If stakes exist but all yield weights are zero (e.g. midnight index 1
        // where zeroCouponYield hasn't been set yet), return empty yields
        if (denom == 0 || cacheCount == 0) {
            return yields;
        }

        yields = new IK2YieldFacet.MaturityYieldWithShares[](cacheCount);

        for (uint256 j = 0; j < cacheCount; j++) {
            uint256 maturityWeight = Math.mulDiv(cache[j].weight, Constants.WAD, denom);
            uint256 yieldForMaturity = Math.mulDiv(totalK2YieldForLP, maturityWeight, Constants.WAD);

            uint256 totalShares = r.lpK2YieldGlobal[lpToken][cache[j].maturityId].totalShares;

            yields[j] = IK2YieldFacet.MaturityYieldWithShares({
                maturityId: cache[j].maturityId, k2Yield: yieldForMaturity, totalShares: totalShares
            });
        }

        return yields;
    }

    /**
     * @notice Internal helper: compute distribution for KVCM stakers using pre-computed circulatingSupply
     */
    function _calcDistributionForKVCMStakersWithSupply(
        uint64 midNightIndex,
        uint256 totalK2YieldForKVCM,
        uint256 circulatingSupply
    ) internal view returns (IK2YieldFacet.MaturityYieldWithShares[] memory yields) {
        if (totalK2YieldForKVCM == 0) {
            return yields;
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        if (config.stakingManager == address(0)) {
            revert Errors.InvalidStakingManagerAddress();
        }

        address maturityManager = config.maturityManager;
        if (maturityManager == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        uint256 referenceTimestamp = IMaturityManager(maturityManager).getMidnightTimestampForIndex(midNightIndex);

        // Use the version that accepts circulatingSupply
        (IRollUpdateFacet.YieldCurvePoint[] memory yieldCurveValues,,,) = IRollUpdateFacet(address(this))
            .getFullCurveValuesForIntervalWithSupply(midNightIndex, referenceTimestamp, circulatingSupply);

        uint256 curveLen = yieldCurveValues.length;

        if (curveLen == 0) {
            revert Errors.NoActiveYieldCurve(midNightIndex);
        }

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        uint256 denom;
        Weight[40] memory cache;
        uint256 cacheCount = 0;

        for (uint256 idx = 0; idx < curveLen; idx++) {
            if (cacheCount >= 40) break;

            uint256 maturityId = yieldCurveValues[idx].maturityId;
            uint256 kvcmTotalStaked =
                IKvcmStakingFacet(config.stakingManager).getKvcmLockedForMaturity(SafeCast.toUint128(maturityId));

            if (kvcmTotalStaked == 0) continue;

            uint256 w = Math.mulDiv(kvcmTotalStaked, yieldCurveValues[idx].zeroCouponYieldCurve, Constants.WAD);

            cache[cacheCount] = Weight({maturityId: maturityId, weight: w});
            denom += w;
            cacheCount++;
        }

        // If no KVCM stakes or all yield weights zero (initial conditions), return empty yields
        if (cacheCount == 0 || denom == 0) {
            return yields;
        }

        yields = new IK2YieldFacet.MaturityYieldWithShares[](cacheCount);

        for (uint256 j = 0; j < cacheCount; j++) {
            uint256 maturityWeight = Math.mulDiv(cache[j].weight, Constants.WAD, denom);
            uint256 yieldForMaturity = Math.mulDiv(totalK2YieldForKVCM, maturityWeight, Constants.WAD);

            uint256 totalShares = r.kvcmK2YieldGlobal[cache[j].maturityId].totalShares;

            yields[j] = IK2YieldFacet.MaturityYieldWithShares({
                maturityId: cache[j].maturityId, k2Yield: yieldForMaturity, totalShares: totalShares
            });
        }

        return yields;
    }

    function _calcAbsoluteUtilisation(uint256 G, uint256 L) internal view returns (uint256) {
        if (G + L == 0) return 0;

        (uint256 k2Supply,) = _getLatestTokensSupply();

        if (k2Supply == 0) revert Errors.KVCMCirculatingSupplyIsZero();

        // in this rare case
        if (k2Supply < G) revert Errors.K2StakedExceedsSupply(G, k2Supply);
        if (k2Supply < L) revert Errors.K2InLPExceedsSupply(L, k2Supply);

        uint256 num = 2 * Math.mulDiv(G, L, Constants.WAD);
        uint256 denom = Math.mulDiv(G, k2Supply - G, Constants.WAD);

        denom += Math.mulDiv(L, k2Supply - L, Constants.WAD);

        if (denom == 0) {
            return 0;
        }

        return Math.mulDiv(num, Constants.WAD, denom);
    }

    /// num : ( Cir - S ) * L^2
    /// denom : Cir * ( L^2 + G^2 )
    /// weight = num / denom
    /// result = totalK2Yield * utilisation * weight
    /// This will calculate the yield for k2 stakers
    function _calcK2YforK2Stakers(K2YforK2StakersParams memory params) internal view returns (uint256) {
        if (params.totalK2Yield == 0) return 0;

        if (params.L == 0) return 0;
        if (params.G == 0) return 0;

        (, uint256 kvcmSupply) = _getLatestTokensSupply();

        // Validate S <= Cir (KVCM staked cannot exceed circulating supply)
        if (kvcmSupply < params.kvcmStaked) revert Errors.KVCMStakedExceedsSupply(params.kvcmStaked, kvcmSupply);

        uint256 LSq = Math.mulDiv(params.L, params.L, Constants.WAD); // Scale e18
        uint256 GSq = Math.mulDiv(params.G, params.G, Constants.WAD); // Scale e18

        uint256 supplyDiff = kvcmSupply - params.kvcmStaked;
        uint256 num = Math.mulDiv(supplyDiff, LSq, Constants.WAD);
        uint256 denom = Math.mulDiv(kvcmSupply, (LSq + GSq), Constants.WAD);

        if (denom == 0) {
            return 0;
        }

        uint256 weight = Math.mulDiv(num, Constants.WAD, denom);
        return Math.mulDiv(Math.mulDiv(params.totalK2Yield, params.utilisation, Constants.WAD), weight, Constants.WAD);
    }

    /// num :  S * L^2
    /// denom : Cir * ( L^2 + G^2 )
    /// weight = num / denom
    /// result = totalK2Yield * utilisation * weight
    function _calcK2YForKVCMStakers(K2YKVCMStakers memory params) internal view returns (uint256) {
        if (params.totalK2Yield == 0) return 0;
        if (params.kvcmStaked == 0) return 0;
        if (params.L == 0) return 0;
        if (params.G == 0) return 0;

        (, uint256 kvcmSupply) = _getLatestTokensSupply();

        uint256 LSq = Math.mulDiv(params.L, params.L, Constants.WAD); // Scale e18
        uint256 GSq = Math.mulDiv(params.G, params.G, Constants.WAD); // Scale e18

        if (kvcmSupply < params.kvcmStaked) revert Errors.KVCMStakedExceedsSupply(params.kvcmStaked, kvcmSupply);

        uint256 num = Math.mulDiv(params.kvcmStaked, LSq, Constants.WAD);
        uint256 denom = Math.mulDiv(kvcmSupply, (LSq + GSq), Constants.WAD);

        if (denom == 0) {
            return 0;
        }

        uint256 weight = Math.mulDiv(num, Constants.WAD, denom);
        return Math.mulDiv(Math.mulDiv(params.totalK2Yield, params.utilisation, Constants.WAD), weight, Constants.WAD);
    }

    /**
     * @notice Validates sequential processing constraints
     * @param midNightIndex The current midnight index being processed
     * @param lastProcessed The last processed midnight index
     */
    function _validateSequentialProcessing(uint64 midNightIndex, uint64 lastProcessed) internal pure {
        // Prevent duplicate processing
        if (lastProcessed > 0 && midNightIndex <= lastProcessed) {
            revert Errors.K2YMidnightIndexAlreadyProcessed(midNightIndex, lastProcessed);
        }
    }

    /**
     * @notice Verify that no future settlement is attempted.
     * @param midNightIndex The midnight index to validate.
     */
    function _validateNoFutureSettlement(uint64 midNightIndex) internal view {
        IMaturityManager mm = IMaturityManager(RewardManagerStorage.rmConfig().maturityManager);
        uint256 currentMidnightIndex = mm.getMidnightIndexForTimestamp(block.timestamp);

        // Disallow settling an index that hasn't happened yet
        if (midNightIndex > currentMidnightIndex) {
            revert Errors.InvalidFutureSettlement(midNightIndex, currentMidnightIndex);
        }
    }

    /**
     * @notice Validates KVCM yield settlement for a given midnight index
     * @param midNightIndex The midnight index to validate
     * @param kvcmLockYieldLayout The KVCM lock yield layout storage
     */
    function _validateKVCMYieldSettlement(
        uint64 midNightIndex,
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout
    ) internal view {
        // Ensure KVCM yield distribution was completed first (ensures accurate curve values)
        // Check that KVCM yield was distributed for this midnight index or later
        uint128 lastKVCMYieldDistribution = kvcmLockYieldLayout.lastMidnightIndexYieldDistribution;
        if (lastKVCMYieldDistribution == 0 || lastKVCMYieldDistribution < midNightIndex) {
            revert Errors.KVCMYieldIntervalNotSettled(midNightIndex);
        }

        // This check is relevant here as the yield curve values are finalized at this point.
        // Hence we want to be sure that when the k2 yield is distributed,
        // the kvcm yield for the same midnight index is also distributed.
        RewardManagerStorage.IntervalData storage intervalData = kvcmLockYieldLayout.intervalData[midNightIndex];
        if (!intervalData.settled) {
            revert Errors.KVCMYieldIntervalNotSettled(midNightIndex);
        }
    }

    /**
     * @notice Validates maturity yields array constraints
     * @param yields The array to validate
     */
    function _validateMaturityYieldsArray(IK2YieldFacet.MaturityYieldWithShares[] memory yields) internal pure {
        // Validate inputs
        if (yields.length == 0) {
            revert Errors.EmptyArray();
        }

        // Validate array size (max 40 maturities)
        if (yields.length > 40) {
            revert Errors.ArrayTooLarge(yields.length, 40);
        }

        // Validate maturity ids
        _validateMaturityIdsWithShares(yields);
    }

    /**
     * @notice Transfers K2 tokens from escrow to rewards manager if amount > 0
     * @param amount The amount to transfer
     */
    function _transferK2FromEscrow(uint256 amount) internal {
        if (amount > 0) {
            RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
            IProtocolRewardsEscrow(config.protocolRewardsEscrow).transferK2ToRewardManager(amount);
        }
    }

    /**
     * @notice Validates maturity IDs for MaturityYieldWithShares array
     * @param maturityYields The array to validate
     */
    function _validateMaturityIdsWithShares(IK2YieldFacet.MaturityYieldWithShares[] memory maturityYields)
        internal
        pure
    {
        unchecked {
            for (uint256 i = 0; i < maturityYields.length; i++) {
                uint256 currentMaturityId = maturityYields[i].maturityId;

                if (currentMaturityId > uint256(type(uint128).max)) {
                    revert Errors.InvalidMaturityId(currentMaturityId);
                }

                if (i > 0) {
                    uint256 prevMaturityId = maturityYields[i - 1].maturityId;
                    if (currentMaturityId <= prevMaturityId) {
                        revert Errors.MaturityIdsNotSorted(prevMaturityId, currentMaturityId);
                    }
                }
            }
        }
    }
}
