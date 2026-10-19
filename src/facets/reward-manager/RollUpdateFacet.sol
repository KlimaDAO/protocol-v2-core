// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

//interfaces
import {IRewardManagerConfigFacet} from "src/interfaces/RewardManager/IRewardManagerConfigFacet.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {IProtocolMinter} from "src/interfaces/IProtocolMinter.sol";
import {IMaturityManager} from "src/interfaces/IMaturityManager.sol";
import {IRollUpdateFacet} from "src/interfaces/RewardManager/IRollUpdateFacet.sol";
import {IProtocolSupplyOracle} from "src/interfaces/IProtocolSupplyOracle.sol";
import {IKvcmStakingFacet} from "src/interfaces/StakingManager/IKvcmStakingFacet.sol";

//libraries
import {RewardManagerStorage} from "src/libraries/storage/RewardManagerStorage.sol";
import {Constants} from "src/libraries/Constants.sol";
import {Errors} from "src/libraries/Errors.sol";
import {CarbonSystemRoleLib} from "src/libraries/CarbonSystemRoleLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {KvcmIncentivesCurveMathLib} from "src/libraries/reward-manager/KvcmIncentivesCurveMathLib.sol";
import {LibUtils} from "src/libraries/LibUtils.sol";

contract RollUpdateFacet is IRollUpdateFacet {
    /**
     * @dev Modifier to check if sender has admin role
     */
    modifier onlyAdmin() {
        address accessManager = RewardManagerStorage.configLayout().accessManager;
        (bool hasCarbonSystemAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (!hasCarbonSystemAdminRole) {
            // just change the error type to what tests expect
            revert Errors.CallerNotAdmin();
        }
        _;
    }

    modifier onlyStateUpdater() {
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();

        (bool hasRole,) = IAccessManager(rmConfig.accessManager)
            .hasRole(CarbonSystemRoleLib.REWARDS_MANAGER_STATE_UPDATER, msg.sender);

        if (!hasRole) {
            revert Errors.NotRewardManagerStateUpdater();
        }
        _;
    }

    /**
     * @notice Calculate the kvcm lock yield for the interval.
     * @dev this function needs to be wired to a block number to return the correct current circ supply
     * @dev midnightIndex. index of CURRENT interval. yield stributed for index - 1, curve and yield calculated for index
     * @dev need to rename this as it sounds like we are calc and distribute FOR these midnight indices, while it's actually AT these midnight indeices
     * @param midnightIndex The midnight index.
     * @return yields The maturity yields.
     * @return currentCirculatingSupply The current circulating supply.
     * @return discountParameter The discount parameter.
     */
    function computeDayAheadLockYieldsAtIndex(uint128 midnightIndex)
        external
        view
        returns (MaturityYields[] memory yields, uint256 currentCirculatingSupply, uint256 discountParameter)
    {
        // @dev this does NOT include the yield that is calculated for this distribution not minted yet
        currentCirculatingSupply =
            IProtocolSupplyOracle(RewardManagerStorage.configLayout().protocolSupplyOracle).getKvcmSupply();

        if (currentCirculatingSupply == 0) {
            revert Errors.InvalidCirculatingSupply(midnightIndex, currentCirculatingSupply);
        }

        uint256 lastDistribution = RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution;

        // If no prior distribution, initalize current maturities
        if (lastDistribution == 0) {
            return _noPriorRoll(midnightIndex, currentCirculatingSupply);
        }

        // @dev given the circulating supply issue, this function will only be off-chain at a block number.
        // therefore we always enforce the order and disallow onchain historical lookups
        if (midnightIndex != lastDistribution + 1) {
            revert Errors.InvalidPreviousMidnightIndex(midnightIndex, lastDistribution);
        }

        uint256 referenceTimestamp = IMaturityManager(RewardManagerStorage.configLayout().maturityManager)
            .getMidnightTimestampForIndex(midnightIndex);

        (YieldCurvePoint[] memory yieldCurve,, uint256 computedDiscountParameter, uint256 rawTotalLockIssue) =
            _getFullCurveValuesForInterval(midnightIndex, referenceTimestamp, currentCirculatingSupply);

        yields = _createMaturityYieldsArray(midnightIndex, yieldCurve);

        return (yields, currentCirculatingSupply, computedDiscountParameter);
    }

    /**
     * @notice Distribute the kvcm lock yield for the interval.
     * @param targetMidnightIndex The target midnight index.
     * @param discountParameter The discount parameter.
     * @param circulatingSupplySnapshot The circulating supply snapshot.
     * @param maturityYields The maturity yields.
     */
    function distributeKvcmLockYieldForInterval(
        uint256 targetMidnightIndex,
        uint256 discountParameter,
        uint256 circulatingSupplySnapshot,
        MaturityYields[] memory maturityYields
    ) external onlyStateUpdater {
        if (RewardManagerStorage.managerPauseLayout().systemPaused) {
            revert Errors.SystemPaused();
        }

        if (circulatingSupplySnapshot == 0) {
            revert Errors.InvalidCirculatingSupply(targetMidnightIndex, circulatingSupplySnapshot);
        }

        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();
        IMaturityManager maturityManager = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);

        uint256 previousMidnightIndex = targetMidnightIndex > 0 ? targetMidnightIndex - 1 : targetMidnightIndex;

        // --- genesis (runs once on protocol deployment) ---
        if (yieldLayout.intervalData[previousMidnightIndex].rollTimestamp == 0) {
            uint256 supply0 = yieldLayout.intervalData[previousMidnightIndex].supplyAtRoll;
            if (supply0 == 0) supply0 = circulatingSupplySnapshot;

            uint256 lastMidnightTimestamp = maturityManager.getMidnightTimestampForIndex(previousMidnightIndex);

            _genesisInit(yieldLayout, previousMidnightIndex, lastMidnightTimestamp, supply0, maturityManager);
        }

        uint256 referenceTimestamp = maturityManager.getMidnightTimestampForIndex(targetMidnightIndex);
        (uint256 firstActiveMaturityId, uint256 lastActiveMaturityId) =
            maturityManager.getYieldBearingMaturityRangeForTimestamp(referenceTimestamp);

        _validateNoFutureSettlement(targetMidnightIndex);

        // if not sequential, revert
        _validateSequentialDistribution(targetMidnightIndex, yieldLayout.lastMidnightIndexYieldDistribution);
        // validate passed array
        _validateMaturityYieldsArray(targetMidnightIndex, firstActiveMaturityId, lastActiveMaturityId, maturityYields);

        // if already settled interval, revert
        if (yieldLayout.intervalData[targetMidnightIndex].settled) {
            revert Errors.IntervalAlreadySettled(targetMidnightIndex);
        }

        // mint previous interval yield
        uint256 totalYieldToMint = 0;

        for (uint256 i = 0; i < maturityYields.length; ++i) {
            totalYieldToMint += _settleMaturityRoll(
                yieldLayout, previousMidnightIndex, targetMidnightIndex, maturityYields[i]
            );
        }

        // cleanup expiring maturity allocations if needed
        _cleanupExpiringMaturity(targetMidnightIndex, maturityManager);

        // store interval data
        uint256 supplyAtRoll = circulatingSupplySnapshot + totalYieldToMint;
        RewardManagerStorage.IntervalData storage intervalData = yieldLayout.intervalData[targetMidnightIndex];
        intervalData.rollTimestamp = SafeCast.toUint128(block.timestamp);
        intervalData.discountParameterAtRoll = SafeCast.toUint128(discountParameter);
        intervalData.supplyAtRoll = supplyAtRoll;
        intervalData.kVCMYield = totalYieldToMint;
        intervalData.settled = true;

        // store last midnight index yield distribution
        RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution =
            SafeCast.toUint128(targetMidnightIndex);

        // Mint Yield to Rewards Manager
        if (totalYieldToMint > 0) {
            IProtocolMinter(RewardManagerStorage.configLayout().protocolMinter)
                .mintKvcmToRewardManager(totalYieldToMint);
        }

        emit YieldDistributionSettled(
            totalYieldToMint, targetMidnightIndex, block.timestamp, discountParameter, supplyAtRoll
        );
    }

    /**
     * @notice Get the full curve values for the interval.
     * @param targetMidnightIndex The target midnight index.
     * @param referenceTimestamp The reference timestamp.
     * @return yieldCurve The yield curve.
     * @return totalKvcmLocked The total kvcm locked.
     * @return discountParameter The discount parameter.
     * @return rawTotalLockIssue The raw total lock issue.
     */
    function getFullCurveValuesForInterval(uint256 targetMidnightIndex, uint256 referenceTimestamp)
        external
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalKvcmLocked,
            uint256 discountParameter,
            uint256 rawTotalLockIssue
        )
    {
        uint256 circulatingSupply =
            RewardManagerStorage.kvcmLockYieldLayout().intervalData[targetMidnightIndex].supplyAtRoll;

        return _getFullCurveValuesForInterval(targetMidnightIndex, referenceTimestamp, circulatingSupply);
    }

    /// @inheritdoc IRollUpdateFacet
    function getFullCurveValuesForIntervalWithSupply(
        uint256 targetMidnightIndex,
        uint256 referenceTimestamp,
        uint256 circulatingSupply
    )
        external
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalKvcmLocked,
            uint256 discountParameter,
            uint256 rawTotalLockIssue
        )
    {
        return _getFullCurveValuesForInterval(targetMidnightIndex, referenceTimestamp, circulatingSupply);
    }

    /// @inheritdoc IRollUpdateFacet
    function getFullCurveValues()
        external
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalEffectiveKvcmLocked,
            uint256 discountParameter,
            uint256 rawTotalLockIssue
        )
    {
        uint256 previousMidnightIndex = RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution;
        uint256 indexToProcess = previousMidnightIndex + 1;
        uint256 referenceTimestamp = IMaturityManager(RewardManagerStorage.configLayout().maturityManager)
            .getMidnightTimestampForIndex(indexToProcess);
        uint256 circulatingSupply =
            IProtocolSupplyOracle(RewardManagerStorage.configLayout().protocolSupplyOracle).getKvcmSupply();

        return _getFullCurveValuesForInterval(indexToProcess, referenceTimestamp, circulatingSupply);
    }

    // ********************** INTERNALS **********************

    /**
     * @notice No prior roll.
     * @param midnightIndex The midnight index.
     * @param currentCirculatingSupply The current circulating supply.
     * @return yields The maturity yields.
     * @return circulatingSupply The circulating supply.
     * @return discountParameter The discount parameter.
     */
    function _noPriorRoll(uint256 midnightIndex, uint256 currentCirculatingSupply)
        internal
        view
        returns (MaturityYields[] memory yields, uint256 circulatingSupply, uint256 discountParameter)
    {
        IMaturityManager maturityManager = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);
        uint256 referenceTimestamp = maturityManager.getMidnightTimestampForIndex(midnightIndex);
        (uint256 firstActiveMaturityId, uint256 lastActiveMaturityId) =
            maturityManager.getYieldBearingMaturityRangeForTimestamp(referenceTimestamp);

        uint256 numMaturities = lastActiveMaturityId - firstActiveMaturityId + 1;

        yields = new MaturityYields[](numMaturities);

        for (uint256 i = 0; i < numMaturities; ++i) {
            MaturityYields memory y;
            y.midnightIndex = midnightIndex;
            y.maturityId = firstActiveMaturityId + i;
            y.rawLockIssueForInterval = 0;
            y.zeroCouponYieldCurve = 0;
            yields[i] = y;
        }
        return (yields, currentCirculatingSupply, 0);
    }

    /**
     * @notice Settle the maturity roll.
     * @param yieldLayout The yield layout.
     * @param previousMidnightIndex The previous midnight index.
     * @param currentMidnightIndex The current midnight index.
     * @param maturityYield The maturity yield.
     * @return totalYieldToMint The total yield to mint.
     */
    function _settleMaturityRoll(
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout,
        uint256 previousMidnightIndex,
        uint256 currentMidnightIndex,
        MaturityYields memory maturityYield
    ) internal returns (uint256 totalYieldToMint) {
        uint256 maturityId = maturityYield.maturityId;

        // previous interval yield
        uint256 previousIntervalYield =
            yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].yieldForCurrentInterval;

        // increase pps using the stored yield from previous roll
        uint256 ppsNow = _updatePPSAtRoll(currentMidnightIndex, maturityId, previousIntervalYield);
        uint256 totalSharesNow = _updateSharesAtRoll(currentMidnightIndex, maturityId);

        // store the yield for the current interval to be minted/pps bump at next roll
        yieldLayout.maturityIntervalData[currentMidnightIndex][maturityId].yieldForCurrentInterval =
            LibUtils.to128(maturityYield.rawLockIssueForInterval);

        // mint the previous interval yield
        totalYieldToMint += previousIntervalYield;

        emit MaturityRollSettled(currentMidnightIndex, maturityId, previousIntervalYield, ppsNow, totalSharesNow);
    }

    /**
     * @notice Update the pps at roll.
     * @param currentMidnightIndex The current midnight index.
     * @param maturityId The maturity id.
     * @param maturityYieldForInterval The maturity yield for the interval.
     * @return newPPS The new pps.
     */
    function _updatePPSAtRoll(uint256 currentMidnightIndex, uint256 maturityId, uint256 maturityYieldForInterval)
        internal
        returns (uint256 newPPS)
    {
        uint256 previousMidnightIndex = currentMidnightIndex > 0 ? currentMidnightIndex - 1 : currentMidnightIndex;

        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();

        uint256 ppsAtLastRoll = yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].ppsAtRoll;

        uint256 sharesAtLastRoll = yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].totalSharesAtRoll;

        if (sharesAtLastRoll == 0) {
            // @dev if the shares at last roll are 0, the maturity yield for the interval must be 0
            if (maturityYieldForInterval != 0) {
                revert Errors.InvalidMaturityYieldForInterval(
                    currentMidnightIndex, maturityId, maturityYieldForInterval
                );
            }
            newPPS = Constants.WAD; // define PPS for new maturity
        } else {
            uint256 pastEffectivePrincipal = Math.mulDiv(sharesAtLastRoll, ppsAtLastRoll, Constants.WAD);
            uint256 newEffectivePrincipal = pastEffectivePrincipal + maturityYieldForInterval;

            newPPS = Math.mulDiv(newEffectivePrincipal, Constants.WAD, sharesAtLastRoll);
        }

        // update pps at roll
        yieldLayout.maturityIntervalData[currentMidnightIndex][maturityId].ppsAtRoll = SafeCast.toUint128(newPPS);

        return newPPS;
    }

    /**
     * @notice Update the shares at roll.
     * @param currentMidnightIndex The current midnight index.
     * @param maturityId The maturity id.
     * @return totalSharesNow The total shares now.
     */
    function _updateSharesAtRoll(uint256 currentMidnightIndex, uint256 maturityId)
        internal
        returns (uint256 totalSharesNow)
    {
        uint256 previousMidnightIndex = currentMidnightIndex > 0 ? currentMidnightIndex - 1 : currentMidnightIndex;

        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();

        uint256 sharesAtLastRoll = yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].totalSharesAtRoll;

        // NEW: fallback to running total if prev interval is unset
        if (sharesAtLastRoll == 0 && previousMidnightIndex > 0) {
            uint256 running = yieldLayout.currentMaturityTotals[maturityId].totalSharesForMaturity;

            if (running != 0) sharesAtLastRoll = running;
        }

        uint256 depositsDuringInterval =
            yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].depositsDuringInterval;

        uint256 ppsNow = yieldLayout.maturityIntervalData[currentMidnightIndex][maturityId].ppsAtRoll;
        if (ppsNow == 0) {
            revert Errors.PPSNotSet(currentMidnightIndex, maturityId);
        }

        uint256 newShares =
            (depositsDuringInterval == 0) ? 0 : Math.mulDiv(depositsDuringInterval, Constants.WAD, ppsNow);
        uint256 newTotalShares = sharesAtLastRoll + newShares;

        // update interval data shares storage
        yieldLayout.maturityIntervalData[currentMidnightIndex][maturityId].totalSharesAtRoll =
            SafeCast.toUint128(newTotalShares);

        // update maturity totals shares storage
        yieldLayout.currentMaturityTotals[maturityId].totalSharesForMaturity = newTotalShares;

        // update total effective principal. this includes previous total eff, yield minted, and deposits during the previous interval
        uint256 totalEffectivePrincipalAtRoll = Math.mulDiv(newTotalShares, ppsNow, Constants.WAD);

        yieldLayout.maturityIntervalData[currentMidnightIndex][maturityId].totalEffectivePrincipalAtRoll =
        totalEffectivePrincipalAtRoll;

        return newTotalShares;
    }

    /**
     * @notice Settle the expiring maturity roll.
     * @param y The yield layout.
     * @param currentMidnightIndex The current midnight index.
     * @param firstActiveMaturityId The first active maturity id.
     * @param lastActiveMaturityId The last active maturity id.
     * @param maturityManager The maturity manager.
     */
    function _settleExpiringMaturityRoll(
        RewardManagerStorage.KvcmLockYieldLayout storage y,
        uint256 currentMidnightIndex,
        uint256 firstActiveMaturityId,
        uint256 lastActiveMaturityId,
        IMaturityManager maturityManager
    ) internal {
        // --- detect maturity boundary day & settle the expiring maturity
        {
            // @dev if the current midnight index is 0, revert. This should never happen.
            if (currentMidnightIndex == 0) {
                revert Errors.InvalidMidnightIndex(currentMidnightIndex);
            }

            // Check if a maturity expires at this exact midnight timestamp
            uint256 currMidnightTs = maturityManager.getMidnightTimestampForIndex(currentMidnightIndex);

            // The boundary logic in getActiveMaturityRangeForTimestamp INCLUDES the expiring maturity
            // in yield calculations, so firstActiveMaturityId - 1 would be wrong. Instead, we check
            // if the currMidnightTs matches any maturity's expiration timestamp directly.
            // We use getMaturityIdForMaturityTimestamp which returns type(uint256).max if not a valid maturity boundary
            uint256 expiringId = maturityManager.getMaturityIdForMaturityTimestamp(currMidnightTs);

            // Only process if this is a valid expiring maturity (not max, not 0, within bounds)
            if (expiringId != type(uint256).max && expiringId > 0 && expiringId <= maturityManager.getMaxMaturityId()) {
                // mint the previous interval’s yield and bump PPS at currentMidnightIndex for the expiring maturity
                uint256 prevIntervalYield =
                    y.maturityIntervalData[currentMidnightIndex - 1][expiringId].yieldForCurrentInterval;

                uint256 ppsNow = _updatePPSAtRoll(currentMidnightIndex, expiringId, prevIntervalYield);
                uint256 totalSharesNow = _updateSharesAtRoll(currentMidnightIndex, expiringId);

                // no future yield for the expired id
                y.maturityIntervalData[currentMidnightIndex][expiringId].yieldForCurrentInterval = 0;

                // clean up allocations tied to this maturity on staking manager
                IKvcmStakingFacet(RewardManagerStorage.configLayout().stakingManager)
                    .cleanUpAllocationsForMaturity(expiringId);

                emit MaturityRollSettled(currentMidnightIndex, expiringId, prevIntervalYield, ppsNow, totalSharesNow);
            }
        }
    }

    /**
     * @notice Cleanup allocations for an expiring maturity on boundary days
     * @param currentMidnightIndex The current midnight index
     * @param maturityManager The maturity manager
     */
    function _cleanupExpiringMaturity(uint256 currentMidnightIndex, IMaturityManager maturityManager) internal {
        uint256 currMidnightTs = maturityManager.getMidnightTimestampForIndex(currentMidnightIndex);
        uint256 expiringId = maturityManager.getMaturityIdForMaturityTimestamp(currMidnightTs);

        if (expiringId != type(uint256).max && expiringId > 0 && expiringId <= maturityManager.getMaxMaturityId()) {
            IKvcmStakingFacet(RewardManagerStorage.configLayout().stakingManager)
                .cleanUpAllocationsForMaturity(expiringId);
        }
    }

    // ********************* Internal *********************

    /**
     * @notice Seed the first midnight snapshot for all active maturities to init the protocol
     * @param yStorage The yield layout.
     * @param initMidnightIndex The initial midnight index.
     * @param lastMidnightTimestamp The last midnight timestamp.
     * @param circulatingSupply The circulating supply.
     * @param maturityManager The maturity manager.
     */
    function _genesisInit(
        RewardManagerStorage.KvcmLockYieldLayout storage yStorage,
        uint256 initMidnightIndex,
        uint256 lastMidnightTimestamp,
        uint256 circulatingSupply,
        IMaturityManager maturityManager
    ) private {
        // already initialized
        if (yStorage.intervalData[initMidnightIndex].rollTimestamp != 0) return;

        // Get active maturities for the init timestamp and seed PPS = 1e18 for the genesis roll snapshot
        (uint256 firstActive, uint256 lastActive) =
            maturityManager.getYieldBearingMaturityRangeForTimestamp(lastMidnightTimestamp);

        for (uint256 m = firstActive; m <= lastActive; ++m) {
            RewardManagerStorage.MaturityIntervalData storage maturityIntervalData =
                yStorage.maturityIntervalData[initMidnightIndex][m];

            // pps defined at genesis; shares/effective principal remain zero
            if (maturityIntervalData.ppsAtRoll == 0) {
                maturityIntervalData.ppsAtRoll = SafeCast.toUint128(Constants.WAD);
            }
        }

        // Seed interval snapshot (no mint yet, so supplyAtRoll == circulatingSupply)
        RewardManagerStorage.IntervalData storage intervalData = yStorage.intervalData[initMidnightIndex];
        intervalData.rollTimestamp = SafeCast.toUint128(lastMidnightTimestamp);
        intervalData.discountParameterAtRoll = SafeCast.toUint128(Constants.WAD);
        intervalData.supplyAtRoll = circulatingSupply;
        // intervalData.settled remains false
        yStorage.lastMidnightIndexYieldDistribution = SafeCast.toUint128(initMidnightIndex);
    }

    /**
     * @notice Returns the full active curve for the day ahead, based on previous day locks.
     * @dev Must be called with a specific block number to return the correct current circ supply
     * @return yieldCurve The yield curve values
     * @return totalKvcmLocked The total kvcm locked
     * @return discountParameter The unscaled discount parameter
     * @return rawTotalLockIssue The unscaled total lock issue
     */
    function _getFullCurveValuesForInterval( // uint256 blockNumber, we can add this as a safety check
        uint256 targetMidnightIndex, // midnight index of CURRENT day. so this should run once the interval is complete
        uint256 referenceTimestamp,
        uint256 circulatingSupply
    )
        internal
        view
        returns (
            YieldCurvePoint[] memory yieldCurve,
            uint256 totalKvcmLocked,
            uint256 discountParameter,
            uint256 rawTotalLockIssue
        )
    {
        if (circulatingSupply == 0) {
            revert Errors.ZeroCirculatingSupply(targetMidnightIndex);
        }

        uint256 lastMidnightIndexYieldDistribution =
            RewardManagerStorage.kvcmLockYieldLayout().lastMidnightIndexYieldDistribution;

        _validateIntervalAndIndex(targetMidnightIndex, lastMidnightIndexYieldDistribution);

        // Early out: protocol not rolled yet -> empty curve
        if (lastMidnightIndexYieldDistribution == 0) {
            RewardManagerStorage.RMConfigLayout storage cfg = RewardManagerStorage.configLayout();
            (uint256 firstActive, uint256 lastActive) =
                IMaturityManager(cfg.maturityManager).getYieldBearingMaturityRangeForTimestamp(referenceTimestamp);
            uint256 num = lastActive - firstActive + 1;
            return (_makeZeroCurve(firstActive, num, new uint256[](num)), 0, 0, 0);
        }

        (BuildCurveParams memory params, uint256 totalEffectiveLocked) =
            _gatherCurveInputs(targetMidnightIndex, referenceTimestamp, circulatingSupply);

        uint256 numMaturities = params.maturityBucketKvcmLocked.length;

        totalKvcmLocked = totalEffectiveLocked;

        if (params.totalLockedProportion == 0 || params.gammaSum == 0) {
            return (_makeZeroCurve(params.firstActiveMaturityId, numMaturities, new uint256[](numMaturities)), 0, 0, 0);
        }

        (yieldCurve, discountParameter, rawTotalLockIssue) = _buildCurve(params);

        return (yieldCurve, totalKvcmLocked, discountParameter, rawTotalLockIssue);
    }

    /**
     * @notice Gather the curve inputs.
     * @param targetMidnightIndex The target midnight index.
     * @param referenceTimestamp The reference timestamp.
     * @param circulatingSupply The circulating supply.
     * @return params The parameters.
     * @return totalEffectiveKvcmLocked The total effective kvcm locked.
     */
    function _gatherCurveInputs(uint256 targetMidnightIndex, uint256 referenceTimestamp, uint256 circulatingSupply)
        private
        view
        returns (BuildCurveParams memory params, uint256 totalEffectiveKvcmLocked)
    {
        RewardManagerStorage.RMConfigLayout storage config = RewardManagerStorage.configLayout();

        // ───────────── active range  ─────────────
        (uint256 firstActiveMaturityId, uint256 lastActiveMaturityId) =
            IMaturityManager(config.maturityManager).getYieldBearingMaturityRangeForTimestamp(referenceTimestamp);
        uint256 numMaturities = lastActiveMaturityId - firstActiveMaturityId + 1;

        // ───────────── ΣS, ΣSE, ΣSE² ─────────────
        params.firstActiveMaturityId = firstActiveMaturityId;
        params.maturityEs = new uint256[](numMaturities);
        params.maturityBucketKvcmLocked = new uint256[](numMaturities);
        params.circulatingSupply = circulatingSupply;

        (uint256 D, uint256 C, uint256 totalEffectiveLockedReturned) = _scanMaturities(
            config,
            params,
            targetMidnightIndex,
            referenceTimestamp,
            firstActiveMaturityId,
            lastActiveMaturityId,
            numMaturities
        );

        if (totalEffectiveLockedReturned == 0) return (params, 0);

        totalEffectiveKvcmLocked = totalEffectiveLockedReturned;

        params = _computeGammas(params, D, C, numMaturities);
    }

    /**
     * @notice Scan the maturities.
     * @param config The config.
     * @param params The parameters.
     * @param targetMidnightIndex The target midnight index.
     * @param referenceTimestamp The reference timestamp.
     * @param firstActiveMaturityId The first active maturity id.
     * @param lastActiveMaturityId The last active maturity id.
     * @param numMaturities The number of maturities.
     * @return D The d.
     * @return C The c.
     * @return totalEffectiveLocked The total effective locked.
     */
    function _scanMaturities(
        RewardManagerStorage.RMConfigLayout storage config,
        BuildCurveParams memory params,
        uint256 targetMidnightIndex,
        uint256 referenceTimestamp,
        uint256 firstActiveMaturityId,
        uint256 lastActiveMaturityId,
        uint256 numMaturities
    ) private view returns (uint256 D, uint256 C, uint256 totalEffectiveLocked) {
        RewardManagerStorage.KvcmLockYieldLayout storage yieldLayout = RewardManagerStorage.kvcmLockYieldLayout();

        uint256 lastMidnightIndexYieldDistribution = yieldLayout.lastMidnightIndexYieldDistribution;

        if (targetMidnightIndex > lastMidnightIndexYieldDistribution + 1) {
            revert Errors.InvalidPreviousMidnightIndex(targetMidnightIndex, lastMidnightIndexYieldDistribution);
        }

        IMaturityManager mm = IMaturityManager(config.maturityManager);
        uint256 firstActiveMaturityTimestamp = mm.getMaturityTimestamp(SafeCast.toUint128(firstActiveMaturityId));
        uint256 maturityPeriod = mm.getMaturityPeriod();

        uint256 numeratorD;
        uint256 numeratorC;

        for (uint256 i; i < numMaturities; ++i) {
            uint256 maturityId = firstActiveMaturityId + i;
            uint256 previousMidnightIndex = targetMidnightIndex > 0 ? targetMidnightIndex - 1 : targetMidnightIndex;

            uint256 depositsDuringInterval =
                yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].depositsDuringInterval;

            // @dev we use the PREVIOUS total effective plus all deposits during the previous interval for current total
            // @dev totalEffectivePrincipalAtRoll here includes the minted yield of the previous interval, which is set in distribute
            // @dev the yield calculated here will be applied at NEXT roll.
            uint256 principal = yieldLayout.maturityIntervalData[previousMidnightIndex][maturityId].totalEffectivePrincipalAtRoll
                + depositsDuringInterval;

            params.maturityBucketKvcmLocked[i] = principal;

            uint256 maturityTs = firstActiveMaturityTimestamp + i * maturityPeriod;

            uint256 maturityE =
                KvcmIncentivesCurveMathLib.calculateGridAlignedE(maturityTs, referenceTimestamp, maturityPeriod);
            params.maturityEs[i] = maturityE;

            numeratorD += principal * maturityE;
            numeratorC += principal * ((maturityE * maturityE) / Constants.WAD);

            totalEffectiveLocked += principal;
        }

        if (totalEffectiveLocked == 0) {
            params.totalLockedProportion = 0;
            return (0, 0, 0);
        }

        D = numeratorD / totalEffectiveLocked;
        C = numeratorC / totalEffectiveLocked;

        uint256 supply = params.circulatingSupply;
        if (supply == 0) {
            // If the supply snapshot is zero but there is locked principal, the state is inconsistent and has an error
            if (totalEffectiveLocked != 0) {
                revert Errors.InconsistentSupplyForLocked(targetMidnightIndex, totalEffectiveLocked);
            }
            // No supply and no locked => no curve
            params.totalLockedProportion = 0;
            return (0, 0, 0);
        } else {
            params.totalLockedProportion = Math.mulDiv(totalEffectiveLocked, Constants.WAD, supply);
        }
    }

    // ********************* Validation helpers *********************

    /**
     * @notice Verify the no future settlement.
     * @param targetMidnightIndex The target midnight index.
     */
    function _validateNoFutureSettlement(uint256 targetMidnightIndex) internal view {
        IMaturityManager mm = IMaturityManager(RewardManagerStorage.configLayout().maturityManager);

        uint256 currentMidnightIndex = mm.getMidnightIndexForTimestamp(block.timestamp);

        // Disallow settling an index that hasn't happened yet
        if (targetMidnightIndex > currentMidnightIndex) {
            revert Errors.InvalidFutureSettlement(targetMidnightIndex, currentMidnightIndex);
        }
    }

    /**
     * @notice Verify the sequential distribution.
     * @param currentMidnightIndex The current midnight index.
     * @param lastDistribution The last distribution.
     */
    function _validateSequentialDistribution(uint256 currentMidnightIndex, uint256 lastDistribution) internal view {
        if (currentMidnightIndex != lastDistribution + 1) {
            revert Errors.InvalidPreviousMidnightIndex(currentMidnightIndex, lastDistribution);
        }
    }

    /**
     * @notice Verify the maturity yields array.
     * @param firstActiveMaturityId The first active maturity id.
     * @param lastActiveMaturityId The last active maturity id.
     * @param maturityYields The maturity yields.
     */
    function _validateMaturityYieldsArray(
        uint256 currentMidnightIndex,
        uint256 firstActiveMaturityId,
        uint256 lastActiveMaturityId,
        MaturityYields[] memory maturityYields
    ) internal pure {
        if (firstActiveMaturityId > lastActiveMaturityId) {
            revert Errors.InvalidMaturityRange(firstActiveMaturityId, lastActiveMaturityId);
        }

        uint256 expectedLen = lastActiveMaturityId - firstActiveMaturityId + 1;

        if (maturityYields.length == 0) {
            revert Errors.InvalidMaturityYields(0, expectedLen);
        }

        if (maturityYields.length != expectedLen) {
            revert Errors.InvalidMaturityYields(maturityYields.length, expectedLen);
        }

        if (maturityYields[0].maturityId != firstActiveMaturityId) {
            revert Errors.InvalidMaturityRange(firstActiveMaturityId, maturityYields[0].maturityId);
        }

        if (maturityYields[0].midnightIndex != currentMidnightIndex) {
            revert Errors.InvalidMaturityYields(0, expectedLen);
        }

        for (uint256 i = 1; i < maturityYields.length; ++i) {
            // sequential IDs
            if (maturityYields[i].maturityId != maturityYields[i - 1].maturityId + 1) {
                revert Errors.InvalidMaturityYields(i, expectedLen);
            }
            // consistent midnightIndex
            if (maturityYields[i].midnightIndex != currentMidnightIndex) {
                revert Errors.InvalidMaturityYields(i, expectedLen);
            }
        }
    }

    /**
     * @notice Validate the interval and index.
     * @param targetMidnightIndex The target midnight index.
     */
    function _validateIntervalAndIndex(uint256 targetMidnightIndex, uint256 lastMidnightIndexYieldDistribution)
        internal
        view
    {
        uint256 interval = IRewardManagerConfigFacet(address(this)).getYieldDistributionInterval();
        if (interval == 0) revert Errors.YieldDistributionIntervalNotSet();

        // future lookups will fail
        if (targetMidnightIndex > lastMidnightIndexYieldDistribution + 1) {
            revert Errors.InvalidMidnightIndex(targetMidnightIndex);
        }
    }

    // ********************* getFullCurveValuesForInterval pure helpers *********************

    /**
     * @notice Make the zero curve.
     * @param firstActive The first active.
     * @param num The num.
     * @param bucketLocked The bucket locked.
     * @return yc The yc.
     */
    function _makeZeroCurve(uint256 firstActive, uint256 num, uint256[] memory bucketLocked)
        private
        pure
        returns (YieldCurvePoint[] memory yc)
    {
        yc = new YieldCurvePoint[](num);
        for (uint256 j; j < num; ++j) {
            yc[j] = YieldCurvePoint({
                maturityId: firstActive + j,
                discountFactor: Constants.WAD, // When no principals exist, discount factor should be 1e18
                zeroCouponYieldCurve: 0,
                yieldForCurrentInterval: 0,
                deltaForCurrentPeriod: 0,
                totalKvcmLockedForBucket: bucketLocked.length == 0 ? 0 : bucketLocked[j]
            });
        }
    }

    /**
     * @notice Build the curve.
     * @param p The parameters.
     * @return yieldCurve The yield curve.
     * @return discountParameter The discount parameter.
     * @return rawTotalLockIssue The raw total lock issue.
     */
    function _buildCurve(BuildCurveParams memory p)
        private
        pure
        returns (YieldCurvePoint[] memory yieldCurve, uint256 discountParameter, uint256 rawTotalLockIssue)
    {
        uint256 n = p.maturityBucketKvcmLocked.length;
        yieldCurve = new YieldCurvePoint[](n);

        uint256 gammaCumulative;
        uint256 gammaCumulativeSum;
        uint256 discountParameterNumerator;
        uint256 discountParameterDenominator;
        uint256 rawTotalLockIssueAccumulator;

        unchecked {
            for (uint256 j; j < n; ++j) {
                gammaCumulative += p.gammas[j];
                gammaCumulativeSum = Math.mulDiv(gammaCumulative, Constants.WAD, p.gammaSum);
                uint256 E = p.maturityEs[j];
                uint256 zeroCouponYield =
                    KvcmIncentivesCurveMathLib.calculateZeroCouponYield(p.totalLockedProportion, gammaCumulativeSum, E);
                uint256 discountFactor = KvcmIncentivesCurveMathLib.calculateDiscountFactor(zeroCouponYield, E);

                uint256 bucketTotalLocked = p.maturityBucketKvcmLocked[j];

                (uint256 deltaForCurrentPeriod, uint256 rawLockIssueForPeriod) =
                    KvcmIncentivesCurveMathLib.calculateBucketLockYieldForPeriod(zeroCouponYield, bucketTotalLocked);

                yieldCurve[j] = YieldCurvePoint({
                    maturityId: p.firstActiveMaturityId + j,
                    discountFactor: discountFactor,
                    zeroCouponYieldCurve: zeroCouponYield,
                    yieldForCurrentInterval: rawLockIssueForPeriod,
                    deltaForCurrentPeriod: deltaForCurrentPeriod,
                    totalKvcmLockedForBucket: bucketTotalLocked
                });

                uint256 zTimesS = (zeroCouponYield * bucketTotalLocked) / Constants.WAD;
                discountParameterNumerator += zTimesS * discountFactor;
                discountParameterDenominator += zTimesS;
                rawTotalLockIssueAccumulator += rawLockIssueForPeriod;
            }
        }

        discountParameter =
            discountParameterDenominator == 0 ? 0 : discountParameterNumerator / discountParameterDenominator;
        rawTotalLockIssue = rawTotalLockIssueAccumulator;
    }

    /**
     * @notice Compute the gammas.
     * @param params The parameters.
     * @param D The d.
     * @param C The c.
     * @param numMaturities The number of maturities.
     * @return params The parameters.
     */
    function _computeGammas(BuildCurveParams memory params, uint256 D, uint256 C, uint256 numMaturities)
        private
        pure
        returns (BuildCurveParams memory)
    {
        params.gammas = new uint256[](numMaturities);
        params.gammaSum = 0;

        for (uint256 k; k < numMaturities; ++k) {
            params.gammaSum += _calcAndStoreGamma(params, k, D, C);
        }
        return params;
    }

    /**
     * @notice Calculate and store the gamma.
     * @param params BuildCurveParams
     * @param k The k
     * @param D The d
     * @param C The c
     * @return g The calculate gamma value
     */
    function _calcAndStoreGamma(BuildCurveParams memory params, uint256 k, uint256 D, uint256 C)
        private
        pure
        returns (uint256 g)
    {
        uint256 Ei = params.maturityEs[k];
        g = KvcmIncentivesCurveMathLib.calculateGamma(D, C, Ei);
        params.gammas[k] = g;
    }

    // ********************* Pure helpers *********************

    /**
     * @notice Create the maturity yields array.
     * @param yieldCurve The yield curve.
     * @return yields The maturity yields.
     */
    function _createMaturityYieldsArray(uint256 midnightIndex, YieldCurvePoint[] memory yieldCurve)
        internal
        pure
        returns (MaturityYields[] memory yields)
    {
        yields = new MaturityYields[](yieldCurve.length);
        for (uint256 i = 0; i < yieldCurve.length; ++i) {
            yields[i].midnightIndex = midnightIndex;
            yields[i].maturityId = yieldCurve[i].maturityId;
            yields[i].rawLockIssueForInterval = yieldCurve[i].yieldForCurrentInterval;
            yields[i].zeroCouponYieldCurve = yieldCurve[i].zeroCouponYieldCurve;
        }
    }
}
