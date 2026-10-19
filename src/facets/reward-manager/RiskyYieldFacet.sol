// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {Constants} from "../../libraries/Constants.sol";
import {Errors} from "../../libraries/Errors.sol";
import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";

import {IMaturityManager} from "../../interfaces/IMaturityManager.sol";
import {IStakingManagerViewFacet} from "../../interfaces/StakingManager/IStakingManagerViewFacet.sol";
import {IRollUpdateFacet} from "../../interfaces/RewardManager/IRollUpdateFacet.sol";
import {IProtocolMinter} from "../../interfaces/IProtocolMinter.sol";
import {IRiskyYieldFacet} from "../../interfaces/RewardManager/IRiskyYieldFacet.sol";
import {IKvcmLPStakingFacet} from "../../interfaces/StakingManager/IKvcmLPStakingFacet.sol";
import {IK2StakingFacet} from "../../interfaces/StakingManager/IK2StakingFacet.sol";
import {IKvcmStakingFacet} from "../../interfaces/StakingManager/IKvcmStakingFacet.sol";
import {IQuoterManager} from "../../interfaces/AssetManager/IQuoterManager.sol";
import {IProtocolSupplyOracle} from "../../interfaces/IProtocolSupplyOracle.sol";
import {AeroLPUtilsLib} from "../../libraries/AeroLPUtils.sol";

/**
 * ----* ----* ----* ----
 * beta calculations
 * beta^2 is computed at every stake/unstake of kvcm & k2
 * ----* ----* ----* ----
 */
contract RiskyYieldFacet is IRiskyYieldFacet, ReentrancyGuard {
    modifier onlyStateUpdater() {
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();

        (bool hasIssuerRole,) = IAccessManager(rmConfig.accessManager)
            .hasRole(CarbonSystemRoleLib.REWARDS_MANAGER_STATE_UPDATER, msg.sender);

        if (!hasIssuerRole) {
            revert Errors.NotRewardManagerStateUpdater();
        }

        _;
    }
    modifier onlyStakingManager() {
        if (msg.sender != RewardManagerStorage.configLayout().stakingManager) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    modifier onlyBetaUpdater() {
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();

        (bool hasBetaUpdaterRole,) =
            IAccessManager(rmConfig.accessManager).hasRole(CarbonSystemRoleLib.BETA_UPDATER, msg.sender);

        if (!hasBetaUpdaterRole) {
            revert Errors.NotAuthorized();
        }

        _;
    }

    modifier whenNotPaused() {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    // ---------------------------------------------------------------------
    // Public Functions
    // ---------------------------------------------------------------------
    function updateBetaSqForKvcmSupplyIncrease(uint256 kvcmSupplyChange_, address, uint64 midnightIndex_)
        public
        onlyBetaUpdater
        whenNotPaused
        returns (uint256 betaSq)
    {
        _validateNoFutureCheckpoint(midnightIndex_);
        _carryForwardBetaForDay(midnightIndex_);
        return _updateBetaSqForKvcmSupplyChange(kvcmSupplyChange_, StakeAction.Stake, midnightIndex_);
    }

    function updateBetaSqForKvcmSupplyDecrease(uint256 kvcmSupplyChange_, address, uint64 midnightIndex_)
        public
        onlyBetaUpdater
        whenNotPaused
        returns (uint256 betaSq)
    {
        _validateNoFutureCheckpoint(midnightIndex_);
        _carryForwardBetaForDay(midnightIndex_);
        return _updateBetaSqForKvcmSupplyChange(kvcmSupplyChange_, StakeAction.Unstake, midnightIndex_);
    }

    function updateBetaSqForKvcmAllocation(uint256 kvcmAllocation_, address carbonClass_, uint64 midnightIndex_)
        public
        onlyStakingManager
        whenNotPaused
        returns (uint256 betaSq)
    {
        _validateNoFutureCheckpoint(midnightIndex_);
        _carryForwardBetaForDay(midnightIndex_);
        return _updateBetaSqForKvcmAction(kvcmAllocation_, carbonClass_, StakeAction.Stake, midnightIndex_);
    }

    function updateBetaSqForKvcmDeallocation(uint256 kvcmAllocation_, address carbonClass_, uint64 midnightIndex_)
        public
        onlyStakingManager
        whenNotPaused
        returns (uint256 betaSq)
    {
        _validateNoFutureCheckpoint(midnightIndex_);
        _carryForwardBetaForDay(midnightIndex_);
        return _updateBetaSqForKvcmAction(kvcmAllocation_, carbonClass_, StakeAction.Unstake, midnightIndex_);
    }

    function updateBetaSqForK2Allocation(uint256 k2Allocation_, address carbonClass_, uint64 midnightIndex_)
        public
        onlyStakingManager
        whenNotPaused
        returns (uint256 betaSq)
    {
        _validateNoFutureCheckpoint(midnightIndex_);
        _carryForwardBetaForDay(midnightIndex_);
        return _updateBetaSqForK2Action(k2Allocation_, carbonClass_, StakeAction.Stake, midnightIndex_);
    }

    function updateBetaSqForK2Deallocation(uint256 k2Allocation_, address carbonClass_, uint64 midnightIndex_)
        public
        onlyStakingManager
        whenNotPaused
        returns (uint256 betaSq)
    {
        _validateNoFutureCheckpoint(midnightIndex_);
        _carryForwardBetaForDay(midnightIndex_);
        return _updateBetaSqForK2Action(k2Allocation_, carbonClass_, StakeAction.Unstake, midnightIndex_);
    }

    function setBetaSqForDay(uint64 midnightIndex, uint256 betaSq) external onlyStateUpdater whenNotPaused {
        if (midnightIndex == 0) {
            revert Errors.InvalidMidnightIndex(midnightIndex);
        }
        if (betaSq == 0) {
            revert Errors.ZeroAmount();
        }

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        if (r.betaSqCache[midnightIndex] != 0) {
            return;
        }

        if (midnightIndex != r.lastNonZeroBetaSqIndex + 1) {
            revert Errors.BetaSqIndexNotAdjacent(midnightIndex, r.lastNonZeroBetaSqIndex);
        }

        r.betaSqCache[midnightIndex] = betaSq;
        r.lastNonZeroBetaSqIndex = midnightIndex;
    }

    /**
     * @notice Computes final lambda values at midnight (VIEW function - no state changes)
     * @dev Should be called at midnight block to capture accurate state
     * @param midNightIndex The midnight index to finalize
     * @return values The computed finalization values
     */
    function computeFinalizedLambdas(uint256 midNightIndex) public view returns (FinalizationValues memory values) {
        if (midNightIndex == 0) {
            return values;
        }

        RewardManagerStorage.RMConfigLayout storage c = RewardManagerStorage.rmConfig();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.DailyLambdaCache storage dailyLambdaCache = r.dailyLambdaCache[midNightIndex];

        // Day N window = [midnight(N-1), midnight(N)).
        uint256 midnightStartTimestamp =
            IMaturityManager(c.maturityManager).getMidnightTimestampForIndex(midNightIndex - 1);
        uint256 midnightEndTimestamp = IMaturityManager(c.maturityManager).getMidnightTimestampForIndex(midNightIndex);

        // Check if already finalized
        if (dailyLambdaCache.lastLambdaUpdateTimestamp == midnightEndTimestamp) {
            // Return existing values
            values.finalGG = dailyLambdaCache.tblambdaGG;
            values.finalG = dailyLambdaCache.tblambdaG;
            values.finalQ = dailyLambdaCache.tblambdaQ;
            return values;
        }

        // Accumulate remaining period. A day with no staking activity has an
        // untouched cache (lastUpdate == 0): accumulate the full window from
        // its start, mirroring updateRewardsProportions.
        uint256 lastUpdate = dailyLambdaCache.lastLambdaUpdateTimestamp;
        if (lastUpdate == 0) {
            lastUpdate = midnightStartTimestamp;
        }

        // Start with current accumulated values
        values.finalGG = dailyLambdaCache.tblambdaGG;
        values.finalG = dailyLambdaCache.tblambdaG;
        values.finalQ = dailyLambdaCache.tblambdaQ;

        if (lastUpdate < midnightEndTimestamp) {
            uint256 remainingDelta = midnightEndTimestamp - lastUpdate;

            uint256 betaSq = _resolveBetaSqForDay(midNightIndex);
            // Adding Ceil to avoid beta being rounded down to 0.
            uint256 beta = Math.sqrt(betaSq, Math.Rounding.Ceil);

            // Read state at midnight block (critical timing)
            (uint256 _latestK2Supply, uint256 _latestKvcmSupply) = _getLatestTokensSupply();
            (uint256 _kvcmInAGPool, uint256 _k2InAGPool) = _getLiquidity(c.kvcmK2LPToken);
            (uint256 _kvcmInAQPool,) = _getLiquidity(c.kvcmQLPToken);
            uint256 _totalK2Allocations = _getTotalK2Allocations();

            // Calculate final instantaneous lambdas at midnight
            uint256 lambdaGG = _computeLambdaGG(
                LambdaGGParams({
                    totalK2Allocations: _totalK2Allocations,
                    k2InAGPool: _k2InAGPool,
                    kvcmInAQPool: _kvcmInAQPool,
                    kvcmSupply: _latestKvcmSupply
                })
            );
            uint256 lambdaG = _computeLambdaG(
                LambdaGParams({lambdaGG: lambdaGG, kvcmInAGPool: _kvcmInAGPool, kvcmInAQPool: _kvcmInAQPool})
            );
            uint256 lambdaQ = _computeLambdaQ(LambdaQParams({lambdaGG: lambdaGG, lambdaG: lambdaG}));

            // Add final accumulation
            values.finalGG += _calculateTimeBetalambda(remainingDelta, beta, lambdaGG);
            values.finalG += _calculateTimeBetalambda(remainingDelta, beta, lambdaG);
            values.finalQ += _calculateTimeBetalambda(remainingDelta, beta, lambdaQ);
        }
    }

    /**
     * @notice Stores finalized lambda values (UPDATE function - only writes)
     * @dev Takes pre-computed values from computeFinalizedLambdas()
     * @param midNightIndex The midnight index to finalize
     * @param values The finalization values computed at midnight
     */
    function setFinalizedLambdas(uint64 midNightIndex, FinalizationValues calldata values)
        external
        onlyStateUpdater
        whenNotPaused
    {
        if (midNightIndex == 0) {
            revert Errors.InvalidMidnightIndex(midNightIndex);
        }

        _validateNoFutureSettlement(midNightIndex);

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.DailyLambdaCache storage dailyLambdaCache = r.dailyLambdaCache[midNightIndex];

        // Day N window = [midnight(N-1), midnight(N)), ends at T(N).
        uint256 midnightEndTimestamp =
            IMaturityManager(config.maturityManager).getMidnightTimestampForIndex(midNightIndex);

        // Validate not already finalized
        if (dailyLambdaCache.lastLambdaUpdateTimestamp == midnightEndTimestamp) {
            revert Errors.LambdasAlreadyFinalized(midNightIndex);
        }

        // Store the computed values
        dailyLambdaCache.tblambdaGG = values.finalGG;
        dailyLambdaCache.tblambdaG = values.finalG;
        dailyLambdaCache.tblambdaQ = values.finalQ;
        dailyLambdaCache.lastLambdaUpdateTimestamp = SafeCast.toUint64(midnightEndTimestamp);

        emit LambdasFinalized(midNightIndex, values.finalGG, values.finalG, values.finalQ);
    }

    /**
     * @notice One-time repair for dailyLambdaCache entries corrupted by old staking code.
     * @dev Re-stamps lastLambdaUpdateTimestamp to the correct midnight boundary without modifying lambda values.
     *      Use when legacy state has lastLambdaUpdateTimestamp overwritten after finalization.
     * @param midnightIndex The midnight index to repair
     */
    function repairFinalizedLambdaCache(uint64 midnightIndex) external onlyStateUpdater whenNotPaused {
        if (midnightIndex == 0) {
            revert Errors.InvalidMidnightIndex(midnightIndex);
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.DailyLambdaCache storage dailyLambdaCache = r.dailyLambdaCache[midnightIndex];

        uint256 midnightEndTimestamp =
            IMaturityManager(config.maturityManager).getMidnightTimestampForIndex(midnightIndex);

        dailyLambdaCache.lastLambdaUpdateTimestamp = SafeCast.toUint64(midnightEndTimestamp);

        emit LambdaCacheRepaired(midnightIndex);
    }

    function updateRewardsProportions(uint256 midNightIndex, uint256 totalK2Allocations)
        public
        onlyStakingManager
        whenNotPaused
    {
        if (midNightIndex == 0) {
            return;
        }

        _validateNoFutureCheckpoint(midNightIndex);

        uint256 betaSq = _carryForwardBetaForDay(midNightIndex);
        if (betaSq == 0) {
            revert Errors.BetaIsZero(midNightIndex);
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        // Adding Ceil to avoid beta being rounded down to 0
        uint256 beta = Math.sqrt(betaSq, Math.Rounding.Ceil); // scale => e9

        // Get latest supplies and liquidity data
        (uint256 _latestK2Supply, uint256 _latestKvcmSupply) = _getLatestTokensSupply();

        (uint256 _kvcmInAGPool, uint256 _k2InAGPool) = _getLiquidity(config.kvcmK2LPToken);
        (uint256 _kvcmInAQPool,) = _getLiquidity(config.kvcmQLPToken);

        // Calculate instantaneous lambdas
        uint256 lambdaGG = _computeLambdaGG(
            LambdaGGParams({
                totalK2Allocations: totalK2Allocations,
                k2InAGPool: _k2InAGPool,
                kvcmInAQPool: _kvcmInAQPool,
                kvcmSupply: _latestKvcmSupply
            })
        );
        uint256 lambdaG = _computeLambdaG(
            LambdaGParams({lambdaGG: lambdaGG, kvcmInAGPool: _kvcmInAGPool, kvcmInAQPool: _kvcmInAQPool})
        );
        uint256 lambdaQ = _computeLambdaQ(LambdaQParams({lambdaGG: lambdaGG, lambdaG: lambdaG}));

        // Calculate time-beta weighted increment using ELAPSED time.
        // Day N window starts at T(N-1) = getMidnightTimestampForIndex(N-1).
        uint256 midnightStartTimestamp =
            IMaturityManager(config.maturityManager).getMidnightTimestampForIndex(midNightIndex - 1);

        // Increment and store time-beta weighted lambdas
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.DailyLambdaCache storage dailyLambdaCache = r.dailyLambdaCache[midNightIndex];

        // Calculate deltaTime as ELAPSED time since last update or midnight start
        uint256 lastUpdateTimestamp = dailyLambdaCache.lastLambdaUpdateTimestamp;
        uint256 deltaTime;

        if (lastUpdateTimestamp > 0) {
            // Time elapsed since last update
            deltaTime = block.timestamp - lastUpdateTimestamp;
        } else {
            // Time elapsed since midnight period started
            deltaTime = block.timestamp - midnightStartTimestamp;
        }

        dailyLambdaCache.tblambdaGG += _calculateTimeBetalambda(deltaTime, beta, lambdaGG);
        dailyLambdaCache.tblambdaG += _calculateTimeBetalambda(deltaTime, beta, lambdaG);
        dailyLambdaCache.tblambdaQ += _calculateTimeBetalambda(deltaTime, beta, lambdaQ);

        // Update the timestamp to current block time
        dailyLambdaCache.lastLambdaUpdateTimestamp = uint64(block.timestamp);
    }

    // ---------------------------------------------------------------------
    // Public: Getters: Returns the beta value (Scale : e9)
    // ---------------------------------------------------------------------
    /**
     * @notice Returns the beta value for a given midnightIndex.
     * @param midnightIndex The midnightIndex to get beta for.
     * @return The beta value (scale = e9).
     */
    function getBeta(uint64 midnightIndex) public view returns (uint256) {
        // e9
        uint256 betaSq = _getBetaSqForDay(midnightIndex);
        // Adding Ceil to avoid beta being rounded down to 0
        return Math.sqrt(betaSq, Math.Rounding.Ceil);
    }

    /**
     * @notice Returns the last processed midnight index for a specific LP token
     * @param lpToken The LP token address
     * @return The last processed midnight index for the LP token
     */
    function getLastProcessedMidnightIndexForLP(address lpToken) public view returns (uint256) {
        RewardManagerStorage.RiskyYieldLayout storage r = RewardManagerStorage.riskyYieldLayout();
        return r.lastProcessedMidnightIndexPerLP[lpToken];
    }

    /**
     * @notice Returns the last processed midnight index for K2 stakers
     * @return The last processed midnight index for K2 RY distribution
     */
    function getLastProcessedMidnightIndexForK2() public view returns (uint256) {
        RewardManagerStorage.RiskyYieldLayout storage r = RewardManagerStorage.riskyYieldLayout();
        return r.lastProcessedMidnightIndexK2;
    }

    /**
     * @notice Returns all last processed midnight indices for monitoring
     * @param kvcmK2LP The Kvcm-K2 LP token address
     * @param kvcmQLP The Kvcm-Q LP token address
     * @return kvcmK2LPLastProcessed Last processed index for Kvcm-K2 LP
     * @return kvcmQLPLastProcessed Last processed index for Kvcm-Q LP
     * @return k2LastProcessed Last processed index for K2 stakers
     */
    function getAllLastProcessedMidnightIndices(address kvcmK2LP, address kvcmQLP)
        public
        view
        returns (uint256 kvcmK2LPLastProcessed, uint256 kvcmQLPLastProcessed, uint256 k2LastProcessed)
    {
        RewardManagerStorage.RiskyYieldLayout storage r = RewardManagerStorage.riskyYieldLayout();
        return (
            r.lastProcessedMidnightIndexPerLP[kvcmK2LP],
            r.lastProcessedMidnightIndexPerLP[kvcmQLP],
            r.lastProcessedMidnightIndexK2
        );
    }

    /**
     * @notice Returns the total shares for K2 stakers at current block
     * @dev Should be called at midnight to capture accurate state
     * @return totalShares The total shares for K2 RY distribution
     */
    function getK2StakersTotalShares() public view returns (uint256 totalShares) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        return r.k2StakersRYGlobal.totalShares;
    }

    function getDailyLambdaCache(uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.DailyLambdaCache memory)
    {
        return RewardManagerStorage.rmStorage().dailyLambdaCache[midnightIndex];
    }

    function getBetaSqCache(uint256 midnightIndex) external view returns (uint256) {
        return RewardManagerStorage.rmStorage().betaSqCache[midnightIndex];
    }

    function getLastNonZeroBetaSqIndex() external view returns (uint256) {
        return RewardManagerStorage.rmStorage().lastNonZeroBetaSqIndex;
    }

    function getRYBetaCache(address carbonClass) external view returns (RewardManagerStorage.RYBetaCache memory) {
        return RewardManagerStorage.riskyYieldLayout().betaMappingForCarbonClass[carbonClass];
    }

    /**
     * @notice Computes RY distribution using passed params (for BatchComputeFacet)
     * @dev Pure function - no storage reads required. Skips settlement validation.
     * @param kVCMYield Total KVCM yield for the interval
     * @param discountParam Discount parameter at roll
     * @param tbLambdas Pre-computed finalization values
     * @return distribution The RY distribution
     */
    function computeRYWithLambda(uint256 kVCMYield, uint256 discountParam, FinalizationValues memory tbLambdas)
        public
        pure
        returns (RYDistribution memory distribution)
    {
        // Return zero if no yield
        if (kVCMYield == 0 || discountParam == 0) {
            return distribution;
        }

        uint256 tblambdaGG = tbLambdas.finalGG;
        uint256 tblambdaG = tbLambdas.finalG;
        uint256 tblambdaQ = tbLambdas.finalQ;

        // Compute baseRewards: b * kVCMYield
        uint256 baseRewards = Math.mulDiv(discountParam, kVCMYield, Constants.WAD);
        if (baseRewards == 0) {
            return distribution;
        }

        // Distribute according to beta * lambdas
        distribution.kvcmK2LP = Math.mulDiv(baseRewards, tblambdaG, Constants.LAMBDA_SCALE);
        distribution.kvcmQLP = Math.mulDiv(baseRewards, tblambdaQ, Constants.LAMBDA_SCALE);
        distribution.k2StakersDistribution = Math.mulDiv(baseRewards, tblambdaGG, Constants.LAMBDA_SCALE);
    }

    /**
     * @notice Computes RY for LPs using a pre-computed distribution and circulating supply
     * @dev Use when circulatingSupply is already computed (e.g., from computeDayAheadLockYieldsAtIndex)
     * @param lpToken The LP token address
     * @param midnightIndex The midnight index
     * @param distribution Pre-computed RY distribution
     * @param circulatingSupply The circulating supply to use for curve calculations
     * @return result The maturity yields with shares for the LP token
     */
    function computeRYForLPsWithSupply(
        address lpToken,
        uint256 midnightIndex,
        RYDistribution memory distribution,
        uint256 circulatingSupply
    ) public view returns (LPMaturityYieldWithShares[] memory result) {
        if (lpToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        if (config.stakingManager == address(0)) {
            revert Errors.InvalidStakingManagerAddress();
        }

        address maturityManager = config.maturityManager;
        if (maturityManager == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        // Use the passed distribution directly
        uint256 totalLPRYYield;
        if (lpToken == config.kvcmK2LPToken) {
            totalLPRYYield = distribution.kvcmK2LP;
        } else if (lpToken == config.kvcmQLPToken) {
            totalLPRYYield = distribution.kvcmQLP;
        } else {
            revert Errors.UnsupportedLPToken(lpToken);
        }

        if (totalLPRYYield == 0) {
            return result;
        }

        uint256 referenceTimestamp = IMaturityManager(maturityManager).getMidnightTimestampForIndex(midnightIndex);

        // Use the version that accepts circulatingSupply as parameter
        (IRollUpdateFacet.YieldCurvePoint[] memory yieldCurveValues,,,) = IRollUpdateFacet(address(this))
            .getFullCurveValuesForIntervalWithSupply(midnightIndex, referenceTimestamp, circulatingSupply);

        uint256 curveLen = yieldCurveValues.length;
        if (curveLen == 0) {
            revert Errors.NoActiveYieldCurve(midnightIndex);
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

        if (denom == 0 || cacheCount == 0) {
            return result; // No stakes - return empty
        }

        result = new LPMaturityYieldWithShares[](cacheCount);

        for (uint256 j = 0; j < cacheCount; j++) {
            uint256 maturityWeight = Math.mulDiv(cache[j].weight, Constants.WAD, denom);
            uint256 yieldForMaturity = Math.mulDiv(totalLPRYYield, maturityWeight, Constants.WAD);
            uint256 totalShares = r.lpRYieldGlobal[lpToken][cache[j].maturityId].totalShares;

            result[j] = LPMaturityYieldWithShares({
                maturityId: cache[j].maturityId, riskyYield: yieldForMaturity, totalShares: totalShares
            });
        }
    }

    // ---------------------------------------------------------------------
    // Public: Update Accumulator for LP
    // ---------------------------------------------------------------------
    /**
     * @notice Updates the accumulator for LP tokens using pre-computed values
     * @dev Takes totalShares as parameter - no state reads from current block
     * @param lpToken The LP token address.
     * @param midnightIndex The midnight index.
     * @param maturityYields Array with yields AND totalShares from midnight block.
     */
    function updateAccForLP(address lpToken, uint256 midnightIndex, LPMaturityYieldWithShares[] calldata maturityYields)
        external
        onlyStateUpdater
        nonReentrant
    {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }

        // Validate inputs
        if (lpToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Validate that Kvcm Lock yield has been distributed and settled for this midnight
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout =
            RewardManagerStorage.kvcmLockYieldLayout();

        // Validate sequential processing and prevent double spending for LP RY (per LP token)
        RewardManagerStorage.RiskyYieldLayout storage ryLayout = RewardManagerStorage.riskyYieldLayout();
        uint256 lastProcessed = ryLayout.lastProcessedMidnightIndexPerLP[lpToken];

        _validateNoFutureSettlement(midnightIndex);
        _validateSequentialProcessing(midnightIndex, lastProcessed);
        _validateKVCMYieldIntervalSettled(midnightIndex, kvcmLockYieldLayout);

        // Empty array: zero yield for this LP. Advance index and return.
        if (maturityYields.length == 0) {
            ryLayout.lastProcessedMidnightIndexPerLP[lpToken] = SafeCast.toUint128(midnightIndex);
            return;
        }

        // Validate array size (max 40 maturities)
        if (maturityYields.length > 40) {
            revert Errors.ArrayTooLarge(maturityYields.length, 40);
        }

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        uint256 totalRewardsDistributed = 0;

        // validate maturity ids (modified for new struct)
        _validateMaturityIdsWithShares(maturityYields);

        // Process each maturity
        for (uint256 i = 0; i < maturityYields.length; i++) {
            // Cache struct fields to avoid repeated calldata reads
            LPMaturityYieldWithShares calldata maturityYield = maturityYields[i];
            uint256 maturityId = maturityYield.maturityId;
            uint256 yieldAmount = maturityYield.riskyYield;
            uint256 totalShares = maturityYield.totalShares; // From parameter (midnight value)

            // Skip if no shares (consistency check)
            if (totalShares == 0) continue;

            RewardManagerStorage.GlobalRewardsState storage lpRYieldGlobal = r.lpRYieldGlobal[lpToken][maturityId];

            // ALWAYS update lastKeeperUpdate and snapshot (even for zero yield)
            // This ensures sequential processing works correctly
            lpRYieldGlobal.lastKeeperUpdate = midnightIndex;

            // Update daily snapshot for this maturity
            RewardManagerStorage.AccumulatorSnapshot storage snapshot =
                r.lpRYieldAccSnapshot[lpToken][maturityId][midnightIndex];
            snapshot.midnightAccumulator = lpRYieldGlobal.globalAccumulator;

            // Only update accumulator and rewards if yield > 0
            if (yieldAmount > 0) {
                // USE totalShares FROM PARAMETER (midnight value) instead of reading from storage
                uint256 deltaAccumulator = Math.mulDiv(yieldAmount, Constants.WAD, totalShares);

                // Update global accumulator
                lpRYieldGlobal.globalAccumulator += deltaAccumulator;
                lpRYieldGlobal.totalRewards += yieldAmount;

                // Re-update snapshot with new accumulator
                snapshot.midnightAccumulator = lpRYieldGlobal.globalAccumulator;

                totalRewardsDistributed += yieldAmount;

                emit LPRiskyYieldAccumulatorUpdated(
                    lpToken, SafeCast.toUint64(midnightIndex), maturityId, yieldAmount, lpRYieldGlobal.globalAccumulator
                );
            }
        }

        ryLayout.lastProcessedMidnightIndexPerLP[lpToken] = SafeCast.toUint128(midnightIndex);

        // Call minter to mint reward tokens
        if (totalRewardsDistributed > 0) {
            _mintKvcmToRewardManager(totalRewardsDistributed);
        }
    }

    // ---------------------------------------------------------------------
    // Public: Update Accumulator for K2 Stakers
    // ---------------------------------------------------------------------
    /**
     * @notice Updates the accumulator for K2 stakers using pre-computed totalShares
     * @dev Takes totalShares as parameter - no state reads from current block
     * @param midnightIndex The midnight index.
     * @param k2StakersRewards The rewards amount from computeRY.
     * @param totalShares The total shares captured at midnight block.
     */
    function updateAccForK2Stakers(uint256 midnightIndex, uint256 k2StakersRewards, uint256 totalShares)
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

        // Validate sequential processing and prevent double spending for K2 RY
        RewardManagerStorage.RiskyYieldLayout storage ryLayout = RewardManagerStorage.riskyYieldLayout();
        uint256 lastProcessed = ryLayout.lastProcessedMidnightIndexK2;

        _validateNoFutureSettlement(midnightIndex);
        _validateSequentialProcessing(midnightIndex, lastProcessed);
        _validateKVCMYieldIntervalSettled(midnightIndex, kvcmLockYieldLayout);

        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        RewardManagerStorage.GlobalRewardsState storage k2StakersRYGlobal = r.k2StakersRYGlobal;

        // ALWAYS update lastKeeperUpdate and snapshot (even for zero rewards)
        // This ensures sequential processing works correctly
        k2StakersRYGlobal.lastKeeperUpdate = midnightIndex;

        // Update daily snapshot
        RewardManagerStorage.AccumulatorSnapshot storage snapshot = r.k2RYieldAccSnapshot[midnightIndex];
        snapshot.midnightAccumulator = k2StakersRYGlobal.globalAccumulator;

        // No stakers: allow zero-reward checkpointing so midnight index can progress.
        if (totalShares == 0) {
            // Update the last processed midnight index for K2 RY to prevent reprocessing
            ryLayout.lastProcessedMidnightIndexK2 = SafeCast.toUint128(midnightIndex);

            emit K2StakersRYAccumulatorUpdated(SafeCast.toUint64(midnightIndex), 0, k2StakersRYGlobal.globalAccumulator);
            return;
        }

        // Only update accumulator and rewards if k2StakersRewards > 0
        if (k2StakersRewards > 0) {
            // USE totalShares FROM PARAMETER (midnight value) instead of reading from storage
            uint256 deltaAccumulator = Math.mulDiv(k2StakersRewards, Constants.WAD, totalShares);

            // Update global accumulator
            k2StakersRYGlobal.globalAccumulator += deltaAccumulator;

            k2StakersRYGlobal.totalRewards += k2StakersRewards;

            // Re-update snapshot with new accumulator
            snapshot.midnightAccumulator = k2StakersRYGlobal.globalAccumulator;

            // Call minter to mint reward tokens
            _mintKvcmToRewardManager(k2StakersRewards);
        }

        // Update the last processed midnight index for K2 RY to prevent reprocessing
        ryLayout.lastProcessedMidnightIndexK2 = SafeCast.toUint128(midnightIndex);

        emit K2StakersRYAccumulatorUpdated(
            SafeCast.toUint64(midnightIndex), k2StakersRewards, k2StakersRYGlobal.globalAccumulator
        );
    }

    /**
     * @notice Computes betaSq from a snapshot of allocations across the given carbon classes.
     * @dev Implements equation (20): betaSq = SUM_i [ Ai - Ai*(1-Gi)^2 ]
     *      where Ai = kvcmAllocation_i / kvcmSupply and Gi = k2Allocation_i / k2Supply.
     *      Expands to: betaSq = (1/A) * SUM_i [ ai * gi * (2G - gi) / G^2 ]
     *      Reads live allocations from the StakingManager and live supplies from the oracle.
     *      Call Math.sqrt(betaSq) to obtain beta (scale: e9).
     * @param carbonClasses Non-empty array of carbon class addresses to aggregate over
     * @return betaSq The computed squared beta value (scale: e18, matching getBetaSqCache)
     */
    function computeBetaSqForCarbonClasses(address[] calldata carbonClasses) public view returns (uint256 betaSq) {
        uint256 n = carbonClasses.length;
        if (n == 0) revert Errors.EmptyCarbonClassesArray();

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        (uint256 G, uint256 A) = _getLatestTokensSupply();

        uint256 sumTerms;
        for (uint256 i; i < n; ++i) {
            uint256 ai = IKvcmStakingFacet(config.stakingManager).getKvcmAllocatedForCarbonClass(carbonClasses[i]);
            uint256 gi = IK2StakingFacet(config.stakingManager).getK2AllocatedForCarbonClass(carbonClasses[i]);

            if (ai == 0 || gi == 0) continue;

            uint256 contrib;
            unchecked {
                contrib = Math.mulDiv(Math.mulDiv(ai, gi, G), 2 * G - gi, G);
            }
            sumTerms += contrib;
        }

        betaSq = Math.mulDiv(sumTerms, Constants.WAD, A);
    }

    function _computeAndSyncBeta(address[] memory classes) internal returns (uint256 betaSq) {
        uint256 n = classes.length;
        if (n == 0) return 0;

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
        RewardManagerStorage.RiskyYieldLayout storage ry = RewardManagerStorage.riskyYieldLayout();

        uint256[] memory kvcmAllocs = IKvcmStakingFacet(config.stakingManager).getKvcmAllocationsForClasses(classes);
        uint256[] memory k2Allocs = IK2StakingFacet(config.stakingManager).getK2AllocationsForClasses(classes);
        (uint256 G, uint256 A) = _getLatestTokensSupply();

        uint256 sumTerms;
        for (uint256 i; i < n; ++i) {
            RewardManagerStorage.RYBetaCache storage cache = ry.betaMappingForCarbonClass[classes[i]];
            cache.kvcmAllocation = kvcmAllocs[i];
            cache.k2Allocation = k2Allocs[i];

            if (kvcmAllocs[i] == 0 || k2Allocs[i] == 0) continue;

            uint256 contrib;
            unchecked {
                contrib = Math.mulDiv(Math.mulDiv(kvcmAllocs[i], k2Allocs[i], G), 2 * G - k2Allocs[i], G);
            }
            sumTerms += contrib;
        }
        betaSq = Math.mulDiv(sumTerms, Constants.WAD, A);
    }

    function _computeBetaSqFromClasses(address[] memory classes) internal view returns (uint256 betaSq) {
        uint256 n = classes.length;
        if (n == 0) return 0;

        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();

        uint256[] memory kvcmAllocs = IKvcmStakingFacet(config.stakingManager).getKvcmAllocationsForClasses(classes);
        uint256[] memory k2Allocs = IK2StakingFacet(config.stakingManager).getK2AllocationsForClasses(classes);
        (uint256 G, uint256 A) = _getLatestTokensSupply();

        uint256 sumTerms;
        for (uint256 i; i < n; ++i) {
            if (kvcmAllocs[i] == 0 || k2Allocs[i] == 0) continue;

            uint256 contrib;
            unchecked {
                contrib = Math.mulDiv(Math.mulDiv(kvcmAllocs[i], k2Allocs[i], G), 2 * G - k2Allocs[i], G);
            }
            sumTerms += contrib;
        }
        betaSq = Math.mulDiv(sumTerms, Constants.WAD, A);
    }

    function _computeBetaSqFromAAM() internal view returns (uint256 betaSq) {
        address[] memory classes = IQuoterManager(RewardManagerStorage.rmConfig().aam).getAllCarbonClasses();
        return _computeBetaSqFromClasses(classes);
    }

    function _resolveBetaSqForDay(uint256 midnightIndex) internal view returns (uint256) {
        uint256 betaSq = _getBetaSqForDay(midnightIndex);
        if (betaSq != 0) return betaSq;
        return _computeBetaSqFromAAM();
    }

    function _ensureBetaForDay(uint256 midnightIndex_) internal returns (uint256 betaSq) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        betaSq = r.betaSqCache[midnightIndex_];
        if (betaSq != 0) return betaSq;

        address[] memory classes = IQuoterManager(RewardManagerStorage.rmConfig().aam).getAllCarbonClasses();
        betaSq = _computeAndSyncBeta(classes);

        if (betaSq != 0) {
            r.betaSqCache[midnightIndex_] = betaSq;
            if (midnightIndex_ > r.lastNonZeroBetaSqIndex) {
                r.lastNonZeroBetaSqIndex = midnightIndex_;
            }
        }
    }

    function _carryForwardBetaForDay(uint256 midnightIndex_) internal returns (uint256 betaSq) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();
        betaSq = r.betaSqCache[midnightIndex_];
        if (betaSq != 0) return betaSq;

        uint256 lastIndex = r.lastNonZeroBetaSqIndex;
        if (lastIndex != 0 && lastIndex <= midnightIndex_) {
            betaSq = r.betaSqCache[lastIndex];
            if (betaSq != 0) {
                r.betaSqCache[midnightIndex_] = betaSq;
                if (midnightIndex_ > r.lastNonZeroBetaSqIndex) {
                    r.lastNonZeroBetaSqIndex = midnightIndex_;
                }
                return betaSq;
            }
        }

        return 1e2;
    }

    // ---------------------------------------------------------------------
    // Internal Functions
    // ---------------------------------------------------------------------

    /**
     * @notice Calculates time-beta weighted lambda value
     * @dev Used to accumulate time-weighted proportions during a midnight period
     * @param deltaTime Elapsed time period (seconds)
     * @param beta Beta value (scale e9)
     * @param lambda Lambda proportion value (scale e18)
     * @return Time-weighted proportion (dimensionless)
     */
    function _calculateTimeBetalambda(uint256 deltaTime, uint256 beta, uint256 lambda) internal pure returns (uint256) {
        // Calculate: deltaTime * (beta / 1 day) * (lambda / 1e18)
        // Normalizing by the distribution interval maps a full-day accumulation
        // into LAMBDA_SCALE space (instead of raw seconds).
        return Math.mulDiv(Math.mulDiv(deltaTime, beta, Constants.YIELD_DISTRIBUTION_INTERVAL), lambda, Constants.WAD);
        // return Math.mulDiv(Math.mulDiv(deltaTime, beta, Constants.YIELD_DISTRIBUTION_INTERVAL), lambda, );
        // return Math.mulDiv(Math.mulDiv(deltaTime, beta, Constants.LAMBDA_SCALE), lambda, Constants.WAD);
    }

    /**
     * @notice Retrieves the betaSq value for a given midnightIndex.
     * @dev Rule 1: If betaSq doesn't exist for midnightIndex, read from previous day
     *      Rule 2: If betaSq exists for midnightIndex, use that value
     * @param midnightIndex The midnightIndex to retrieve betaSq for
     * @return The betaSq value for the given midnightIndex (scale = 18)
     */
    function _getBetaSqForDay(uint256 midnightIndex) internal view returns (uint256) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        // Check if betaSq exists for this midnightIndex
        uint256 betaSq = r.betaSqCache[midnightIndex];

        if (betaSq != 0) {
            // Rule 2: betaSq exists for this midnightIndex
            return betaSq;
        }

        // Rule 1: betaSq doesn't exist, use pointer to last non-zero betaSq
        uint256 lastIndex = r.lastNonZeroBetaSqIndex;
        if (lastIndex != 0 && lastIndex <= midnightIndex) {
            return r.betaSqCache[lastIndex];
        }

        return 1e2;
    }

    /**
     * @notice Updates the squared beta value based on Kvcm staking or unstaking actions.
     * @param kvcmAllocation_ The value of Kvcm being staked or unstaked.
     * @param carbonClass_ The address of the associated carbon class.
     * @param stakeAction_ The action being performed (Stake or Unstake).
     * @param midnightIndex_ The midnightIndex for which to update betaSq.
     * @return betaSq The new squared beta value.
     */
    function _updateBetaSqForKvcmAction(
        uint256 kvcmAllocation_,
        address carbonClass_,
        StakeAction stakeAction_,
        uint64 midnightIndex_
    ) internal returns (uint256 betaSq) {
        if (kvcmAllocation_ == 0) {
            return 0;
        }

        if (carbonClass_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        RewardManagerStorage.RiskyYieldLayout storage ry = RewardManagerStorage.riskyYieldLayout();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        (uint256 _latestK2Supply, uint256 _latestKvcmSupply) = _getLatestTokensSupply();

        RewardManagerStorage.RYBetaCache storage betaCache = ry.betaMappingForCarbonClass[carbonClass_];

        // Get previous betaSq value for this midnightIndex (uses _getBetaSqForDay helper)
        uint256 oldBetaSq = _getBetaSqForDay(midnightIndex_); // scale -> e18

        uint256 x = Math.mulDiv(oldBetaSq, _latestKvcmSupply, Constants.WAD);
        // scale -> (e18 * e18 ) / e18 = e18
        uint256 temp = Math.mulDiv(betaCache.k2Allocation, kvcmAllocation_, _latestK2Supply);
        // scale -> (e18 * e18 ) / e18 = e18
        uint256 y = Math.mulDiv(temp, (2 * _latestK2Supply - betaCache.k2Allocation), _latestK2Supply);

        if (stakeAction_ == StakeAction.Stake) {
            betaSq = Math.mulDiv(x + y, Constants.WAD, _latestKvcmSupply, Math.Rounding.Ceil);
            betaCache.kvcmAllocation += kvcmAllocation_;
        } else {
            betaSq = x > y ? Math.mulDiv(x - y, Constants.WAD, _latestKvcmSupply, Math.Rounding.Ceil) : 1e2;
            betaCache.kvcmAllocation -= kvcmAllocation_;
        }

        // Store the new betaSq in the midnightIndex-based cache
        if (betaSq != 0) {
            r.betaSqCache[midnightIndex_] = betaSq;
            if (midnightIndex_ > r.lastNonZeroBetaSqIndex) {
                r.lastNonZeroBetaSqIndex = midnightIndex_;
            }
        }
    }

    /**
     * @notice Updates the squared beta value based on K2 staking or unstaking actions.
     * @param k2Allocation_ The value of K2 being staked or unstaked.
     * @param carbonClass_ The address of the associated carbon class.
     * @param stakeAction_ The action being performed (Stake or Unstake).
     * @param midnightIndex_ The midnightIndex for which to update betaSq.
     * @return betaSq The new squared beta value.
     */
    function _updateBetaSqForK2Action(
        uint256 k2Allocation_,
        address carbonClass_,
        StakeAction stakeAction_,
        uint64 midnightIndex_
    ) internal returns (uint256 betaSq) {
        if (carbonClass_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        RewardManagerStorage.RiskyYieldLayout storage ry = RewardManagerStorage.riskyYieldLayout();
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        (uint256 _latestK2Supply, uint256 _latestKvcmSupply) = _getLatestTokensSupply();

        RewardManagerStorage.RYBetaCache storage betaCache = ry.betaMappingForCarbonClass[carbonClass_];

        // Get previous betaSq value for this midnightIndex (uses _getBetaSqForDay helper)
        uint256 oldBetaSq = _getBetaSqForDay(midnightIndex_);
        uint256 x = Math.mulDiv(oldBetaSq, _latestKvcmSupply, Constants.WAD); // e18 * e18 / e18 = e18

        uint256 temp = Math.mulDiv(betaCache.kvcmAllocation, k2Allocation_, _latestK2Supply);

        if (stakeAction_ == StakeAction.Stake) {
            uint256 factor = 2 * _latestK2Supply - 2 * betaCache.k2Allocation - k2Allocation_;
            uint256 y = Math.mulDiv(temp, factor, _latestK2Supply); // scale -> (e18 * e18 ) / e18 = e18

            betaSq = Math.mulDiv(x + y, Constants.WAD, _latestKvcmSupply, Math.Rounding.Ceil);
            betaCache.k2Allocation += k2Allocation_;
        } else {
            uint256 factor = 2 * _latestK2Supply - 2 * betaCache.k2Allocation + k2Allocation_;
            uint256 y = Math.mulDiv(temp, factor, _latestK2Supply); // scale -> (e18 * e18 ) / e18 = e18

            betaSq = x > y ? Math.mulDiv(x - y, Constants.WAD, _latestKvcmSupply, Math.Rounding.Ceil) : 1e2;
            betaCache.k2Allocation -= k2Allocation_;
        }

        // Store the new betaSq in the midnightIndex-based cache
        if (betaSq != 0) {
            r.betaSqCache[midnightIndex_] = betaSq;
            if (midnightIndex_ > r.lastNonZeroBetaSqIndex) {
                r.lastNonZeroBetaSqIndex = midnightIndex_;
            }
        }
    }

    function _updateBetaSqForKvcmSupplyChange(
        uint256 kvcmSupplyChange_,
        StakeAction stakeAction_,
        uint64 midnightIndex_
    ) internal returns (uint256 betaSq) {
        RewardManagerStorage.RMStorage storage r = RewardManagerStorage.rmStorage();

        (uint256 _latestK2Supply, uint256 _latestKvcmSupply) = _getLatestTokensSupply();

        uint256 _previousKvcmSupply = _latestKvcmSupply;
        if (stakeAction_ == StakeAction.Stake) {
            _previousKvcmSupply -= kvcmSupplyChange_;
        } else {
            _previousKvcmSupply += kvcmSupplyChange_;
        }

        uint256 oldBetaSq = _getBetaSqForDay(midnightIndex_);
        betaSq = Math.mulDiv(oldBetaSq, _previousKvcmSupply, _latestKvcmSupply);

        if (betaSq != 0) {
            r.betaSqCache[midnightIndex_] = betaSq;
            if (midnightIndex_ > r.lastNonZeroBetaSqIndex) {
                r.lastNonZeroBetaSqIndex = midnightIndex_;
            }
        }
    }

    /// ---------------------------------------------------------------------
    /// λGG  =  (A − aAQ)/A  ·  gAG² / ( gAG² + (Σgi)² )
    /// All values are expected to be 18-decimal fixed-point. The result is
    /// returned in the same fixed-point format.
    /// ---------------------------------------------------------------------
    /**
     * @notice Computes the proportion of risky yield allocated to K2 stakers (lambdaGG).
     * @param params Parameters for the lambdaGG calculation.
     * @return The lambdaGG value.
     */
    function _computeLambdaGG(LambdaGGParams memory params) internal pure returns (uint256) {
        uint256 A = params.kvcmSupply; // e18
        uint256 aAQ = params.kvcmInAQPool; // e18

        if (A == 0) {
            revert Errors.KVCMCirculatingSupplyIsZero();
        }

        if (aAQ > A) {
            revert Errors.KvcmAQExceedsSupply(aAQ, A);
        }

        // -----------------------------------------------------------------
        // λGG = (1 − (aAQ  / A)) / ( 1 + ( Σgi / gAG )² )
        // -----------------------------------------------------------------

        // numerator: 1 − (aAQ / A)
        uint256 ratioAQ = Math.mulDiv(aAQ, Constants.WAD, A); // aAQ / A
        uint256 numerator = Constants.WAD - ratioAQ;

        // Guard against division by zero if gAG == 0
        uint256 gAG = params.k2InAGPool;
        if (gAG == 0) return 0;

        // term = Σgi / gAG
        uint256 term = Math.mulDiv(params.totalK2Allocations, Constants.WAD, gAG);

        // (Σgi / gAG)²  -- keep scale 1e18
        uint256 termSq = Math.mulDiv(term, term, Constants.WAD);

        // denominator: 1 + termSq
        uint256 denominator = Constants.WAD + termSq;

        // λGG = numerator / denominator
        return Math.mulDiv(numerator, Constants.WAD, denominator);
    }

    /// ---------------------------------------------------------------------
    /// λG = (1 - λGG) * (√2 / ( √2 + aAQ / aAG ))
    /// ---------------------------------------------------------------------
    /**
     * @notice Computes the proportion of risky yield for AG LP stakers (lambdaG).
     * @param params Parameters for the lambdaG calculation.
     * @return The lambdaG value.
     */
    function _computeLambdaG(LambdaGParams memory params) internal pure returns (uint256) {
        uint256 lambdaGG = params.lambdaGG;
        uint256 aAG = params.kvcmInAGPool;
        uint256 aAQ = params.kvcmInAQPool;

        if (aAG == 0) {
            // No KVCM in AG pool ⇒ λG = 0
            return 0;
        }

        if (lambdaGG > Constants.WAD) {
            revert Errors.LambdaGGExceedsScale(lambdaGG);
        }

        // ratio = aAQ / aAG  (18-dec fixed point)
        uint256 ratio = Math.mulDiv(aAQ, Constants.WAD, aAG);

        // inner = √2 / ( √2 + ratio )
        uint256 inner = Math.mulDiv(Constants.SQRT2_18, Constants.WAD, Constants.SQRT2_18 + ratio);

        // λG = (1 − λGG) · inner
        return Math.mulDiv(Constants.WAD - lambdaGG, inner, Constants.WAD);
    }

    /// ---------------------------------------------------------------------
    /// λQ = 1 − λGG − λG
    /// ---------------------------------------------------------------------
    /**
     * @notice Computes the proportion of risky yield for AQ LP stakers (lambdaQ).
     * @param params Parameters for the lambdaQ calculation.
     * @return The lambdaQ value.
     */
    function _computeLambdaQ(LambdaQParams memory params) internal pure returns (uint256) {
        if (params.lambdaGG + params.lambdaG >= Constants.WAD) {
            return 0;
        }
        return Constants.WAD - (params.lambdaGG + params.lambdaG);
    }

    // ---------------------------------------------------------------------
    // Internal helper functions (data sources)
    // ---------------------------------------------------------------------

    /**
     * @notice Retrieves the latest total supply of Kvcm and K2 tokens.
     * @return uint256 The latest supply of K2.
     * @return uint256 The latest supply of Kvcm.
     */
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

    /**
     * @notice Retrieves the liquidity of a given LP token.
     * @param lpToken The address of the LP token.
     * @return uint256 The KVCM reserve in the pool.
     * @return uint256 The counter-asset (K2 or Q) reserve in the pool.
     */
    function _getLiquidity(address lpToken) internal view returns (uint256, uint256) {
        address kvcmToken = RewardManagerStorage.rmConfig().kvcmToken;
        (uint256 reserve0, uint256 reserve1, address token0, address token1) = AeroLPUtilsLib.getBothReserves(lpToken);
        if (token0 == kvcmToken) {
            return (reserve0, reserve1);
        } else if (token1 == kvcmToken) {
            return (reserve1, reserve0);
        }
        revert Errors.UnsupportedLPToken(lpToken);
    }

    /**
     * @notice Retrieves the total value of price-staked K2.
     * @return The total price-staked value.
     */
    function _getTotalK2Allocations() internal view returns (uint256) {
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();
        return IK2StakingFacet(rmConfig.stakingManager).getTotalK2Allocations();
    }

    /**
     * @notice Validates sequential processing constraints
     * @param midnightIndex The current midnight index being processed
     * @param lastProcessed The last processed midnight index
     */
    function _validateSequentialProcessing(uint256 midnightIndex, uint256 lastProcessed) internal pure {
        // Prevent duplicate processing
        if (lastProcessed > 0 && midnightIndex <= lastProcessed) {
            revert Errors.RYMidnightIndexAlreadyProcessed(midnightIndex, lastProcessed);
        }
    }

    /**
     * @notice Verify that no future settlement is attempted.
     * @param midnightIndex The midnight index to validate.
     */
    function _validateNoFutureSettlement(uint256 midnightIndex) internal view {
        IMaturityManager mm = IMaturityManager(RewardManagerStorage.rmConfig().maturityManager);
        uint256 currentMidnightIndex = mm.getMidnightIndexForTimestamp(block.timestamp);

        // Disallow settling an index that hasn't happened yet
        if (midnightIndex > currentMidnightIndex) {
            revert Errors.InvalidFutureSettlement(midnightIndex, currentMidnightIndex);
        }
    }

    /**
     * @notice Verify that staking checkpoint writes are at most one midnight ahead.
     * @param midnightIndex The midnight index to validate.
     */
    function _validateNoFutureCheckpoint(uint256 midnightIndex) internal view {
        IMaturityManager mm = IMaturityManager(RewardManagerStorage.rmConfig().maturityManager);
        uint256 currentMidnightIndex = mm.getMidnightIndexForTimestamp(block.timestamp);

        // Checkpoint writes may target the next day window (current + 1) but nothing beyond that.
        if (midnightIndex > currentMidnightIndex + 1) {
            revert Errors.InvalidFutureSettlement(midnightIndex, currentMidnightIndex);
        }
    }

    /**
     * @notice Validates KVCM yield settlement for a given midnight index
     * @param midnightIndex The midnight index to validate
     * @param kvcmLockYieldLayout The KVCM lock yield layout storage
     */
    function _validateKVCMYieldIntervalSettled(
        uint256 midnightIndex,
        RewardManagerStorage.KvcmLockYieldLayout storage kvcmLockYieldLayout
    ) internal view {
        // Ensure KVCM yield distribution was completed first (ensures accurate curve values)
        // Check that KVCM yield was distributed for this midnight index or later
        uint128 lastKVCMYieldDistribution = kvcmLockYieldLayout.lastMidnightIndexYieldDistribution;
        if (lastKVCMYieldDistribution == 0 || lastKVCMYieldDistribution < midnightIndex) {
            revert Errors.KVCMYieldIntervalNotSettled(midnightIndex);
        }

        // This check is relevant here as the yield curve values are finalized at this point.
        // Hence we want to be sure that when risky yield is distributed,
        // the kvcm yield for the same midnight index is also distributed.
        RewardManagerStorage.IntervalData storage intervalData = kvcmLockYieldLayout.intervalData[midnightIndex];
        if (!intervalData.settled) {
            revert Errors.KVCMYieldIntervalNotSettled(midnightIndex);
        }
    }

    /**
     * @notice Mints KVCM tokens to reward manager if amount > 0
     * @param amount The amount to mint
     */
    function _mintKvcmToRewardManager(uint256 amount) internal {
        if (amount > 0) {
            RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.rmConfig();
            IProtocolMinter(config.protocolMinter).mintKvcmToRewardManager(amount);
        }
    }

    /**
     * @notice Validates maturity IDs for LPMaturityYieldWithShares array
     * @param maturityYields The array to validate
     */
    function _validateMaturityIdsWithShares(LPMaturityYieldWithShares[] calldata maturityYields) internal pure {
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
