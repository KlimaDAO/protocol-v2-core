// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

//interacets
import {IQuoterRouterFacet} from "src/interfaces/AssetManager/IQuoterRouterFacet.sol";
//libraries
import {OperationsMath} from "src/libraries/aam/OperationsMath.sol";
import {AssetManagerStorage} from "src/libraries/storage/AssetManagerStorage.sol";
import {Constants} from "src/libraries/Constants.sol";
import {Errors} from "src/libraries/Errors.sol";

//openzeppelin
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IProtocolSupplyOracle} from "src/interfaces/IProtocolSupplyOracle.sol";

library RateLimiterLib {
    struct RateLimiterSnapshotValues {
        uint256 liquidSupplySnapshot;
        uint256 kvcmAllocationSnapshot;
        uint256 k2AllocationSnapshot;
    }

    uint256 constant MIN_ALLOCATION_BPS = 100;

    /* --- Default KVCM rate --- */
    function setDefaultKVCMRate(uint64 _defaultKVCMRate) internal {
        AssetManagerStorage.classQuoterLayout().defaultKVCMRate = _defaultKVCMRate;
    }

    function getDefaultKVCMRate() internal view returns (uint64) {
        return AssetManagerStorage.classQuoterLayout().defaultKVCMRate;
    }

    /* --- Default K2 rate --- */

    function setDefaultK2Rate(uint64 _defaultK2Rate) internal {
        AssetManagerStorage.classQuoterLayout().defaultK2Rate = _defaultK2Rate;
    }

    function getDefaultK2Rate() internal view returns (uint64) {
        return AssetManagerStorage.classQuoterLayout().defaultK2Rate;
    }

    /* --- Default allocation rates --- */

    function getKvcmAllocationDefaultRate() internal view returns (uint64) {
        return AssetManagerStorage.classQuoterLayout().defaultKVCMRate;
    }

    function getK2AllocationDefaultRate() internal view returns (uint64) {
        return AssetManagerStorage.classQuoterLayout().defaultK2Rate;
    }

    /* --- Minimum effective allocations --- */

    function setClassMinEffectiveAllocation(address carbonClass, uint128 kvcm, uint128 k2) internal {
        classQuoter(carbonClass); // reverts for unregistered classes
        AssetManagerStorage.classQuoterLayout().classMinEffectiveAllocation[carbonClass] =
            AssetManagerStorage.MinEffectiveAllocation({kvcm: kvcm, k2: k2});
    }

    function getMinEffectiveKvcmAllocation(address carbonClass) internal view returns (uint256) {
        return AssetManagerStorage.classQuoterLayout().classMinEffectiveAllocation[carbonClass].kvcm;
    }

    function getMinEffectiveK2Allocation(address carbonClass) internal view returns (uint256) {
        return AssetManagerStorage.classQuoterLayout().classMinEffectiveAllocation[carbonClass].k2;
    }

    /**
     * @dev Value the allocation limiter snapshots: the pre-txn allocation, floored at the class's
     *      minimum effective allocation so the growth base never sits below it (e.g. after a dust first
     *      allocation). A zero pre-txn allocation needs a floor, as a zero snapshot zeroes the growth math.
     */
    function _allocationValueToStore(address carbonClass, uint256 preTxnAllocationValue, uint256 minEffective)
        internal
        pure
        returns (uint256)
    {
        if (preTxnAllocationValue == 0 && minEffective == 0) {
            revert Errors.MinEffectiveAllocationNotSet(carbonClass);
        }
        return Math.max(preTxnAllocationValue, minEffective);
    }

    /* --- Liquid supply rate limiter --- */

    function updateLiquidSupplyRateLimiter(
        address carbonClass,
        IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory params
    ) internal {
        AssetManagerStorage.ClassQuoterLayout storage quoterLayout = AssetManagerStorage.classQuoterLayout();
        AssetManagerStorage.ClassQuoterData storage classQuoterData = quoterLayout.quoters[classQuoter(carbonClass)];

        // init rate limits
        if (classQuoterData.liquidSupplyRateLimiter.rate == 0) {
            classQuoterData.liquidSupplyRateLimiter.rate = Constants.DEFAULT_KVCM_RATE;
        }

        uint256 currentEffectiveLiquidSupply = calculateCurrentEffectiveClassLiquidSupply(carbonClass, block.timestamp);
        // if rawLiquidSupply is greater than effectiveLiquidSupply, update the rate limiter
        if (params.preTxnLiquidSupply > currentEffectiveLiquidSupply) {
            uint128 newSnapshotValue = SafeCast.toUint128(params.preTxnLiquidSupply);
            classQuoterData.liquidSupplyRateLimiter.lastUpdateTimestamp = SafeCast.toUint64(block.timestamp);

            if (newSnapshotValue != classQuoterData.liquidSupplyRateLimiter.snapshotValue) {
                classQuoterData.liquidSupplyRateLimiter.snapshotValue = newSnapshotValue;
            }
        }
    }

    function getLiquidSupplyRateLimiter(address carbonClass)
        internal
        view
        returns (AssetManagerStorage.RateLimiter memory)
    {
        return AssetManagerStorage.classQuoterLayout().quoters[classQuoter(carbonClass)].liquidSupplyRateLimiter;
    }

    /* --- Kvcm allocation rate limiter --- */

    /// @dev the third argument (amountIfZeroPreTxn) is unused; kept for StakingManager ABI compatibility
    function updateKvcmAllocationRateLimiter(address carbonClass, uint256 preTxnKvcmAllocationValue, uint256) internal {
        AssetManagerStorage.ClassQuoterData storage classQuoterData =
            AssetManagerStorage.classQuoterLayout().quoters[classQuoter(carbonClass)];
        AssetManagerStorage.RateLimiter storage rateLimiter = classQuoterData.kvcmAllocationRateLimiter;

        uint256 allocationValueToStore =
            _allocationValueToStore(carbonClass, preTxnKvcmAllocationValue, getMinEffectiveKvcmAllocation(carbonClass));

        uint256 nowTs = block.timestamp;

        if (rateLimiter.snapshotValue == 0 && rateLimiter.lastUpdateTimestamp == 0) {
            if (rateLimiter.rate == 0) rateLimiter.rate = getDefaultKVCMRate();
            rateLimiter.snapshotValue = SafeCast.toUint128(allocationValueToStore);
            rateLimiter.lastUpdateTimestamp = SafeCast.toUint64(nowTs);
            return;
        }
        uint256 currentEffectiveKvcmAllocation = calculateCurrentEffectiveKvcmAllocation(carbonClass, nowTs);
        if (allocationValueToStore < currentEffectiveKvcmAllocation) {
            _updateKvcmLimiter(classQuoterData, allocationValueToStore, nowTs);
        }
    }

    function _updateKvcmLimiter(
        AssetManagerStorage.ClassQuoterData storage classQuoterData,
        uint256 preTxnAllocationValue,
        uint256 nowTs
    ) internal {
        classQuoterData.kvcmAllocationRateLimiter.lastUpdateTimestamp = SafeCast.toUint64(nowTs);
        if (preTxnAllocationValue != classQuoterData.kvcmAllocationRateLimiter.snapshotValue) {
            classQuoterData.kvcmAllocationRateLimiter.snapshotValue = SafeCast.toUint128(preTxnAllocationValue);
        }
    }

    /* --- K2 allocation rate limiter --- */

    /// @dev the third argument (amountIfZeroPreTxn) is unused; kept for StakingManager ABI compatibility
    function updateK2AllocationRateLimiter(address carbonClass, uint256 preTxnK2AllocationValue, uint256) internal {
        AssetManagerStorage.ClassQuoterData storage classQuoterData =
            AssetManagerStorage.classQuoterLayout().quoters[classQuoter(carbonClass)];
        AssetManagerStorage.RateLimiter storage rateLimiter = classQuoterData.k2AllocationRateLimiter;

        uint256 allocationValueToStore =
            _allocationValueToStore(carbonClass, preTxnK2AllocationValue, getMinEffectiveK2Allocation(carbonClass));

        uint256 nowTs = block.timestamp;

        if (rateLimiter.snapshotValue == 0 && rateLimiter.lastUpdateTimestamp == 0) {
            if (rateLimiter.rate == 0) rateLimiter.rate = getDefaultK2Rate();
            rateLimiter.snapshotValue = SafeCast.toUint128(allocationValueToStore);
            rateLimiter.lastUpdateTimestamp = SafeCast.toUint64(nowTs);
            return;
        }
        uint256 currentEffectiveK2Allocation = calculateCurrentEffectiveK2Allocation(carbonClass, nowTs);
        if (allocationValueToStore < currentEffectiveK2Allocation) {
            _updateK2Limiter(classQuoterData, allocationValueToStore, nowTs);
        }
    }

    function _updateK2Limiter(
        AssetManagerStorage.ClassQuoterData storage classQuoterData,
        uint256 preTxnAllocationValue,
        uint256 nowTs
    ) internal {
        classQuoterData.k2AllocationRateLimiter.lastUpdateTimestamp = SafeCast.toUint64(nowTs);
        if (preTxnAllocationValue != classQuoterData.k2AllocationRateLimiter.snapshotValue) {
            classQuoterData.k2AllocationRateLimiter.snapshotValue = SafeCast.toUint128(preTxnAllocationValue);
        }
    }

    /**
     * @dev LEGACY supply-based bootstrap, superseded by the per-class minimum effective allocation.
     *      No facet calls it; kept only for RateLimiterSeedLib (executed action 045).
     */
    function _initMinAllocation(uint256 amount) internal view returns (uint256 allocationValueToStore) {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        } else {
            uint256 circulatingSupply = IProtocolSupplyOracle(
                    AssetManagerStorage.configLayout().aamConfig.protocolSupplyOracle
                ).getKvcmSupply();
            // .08% of circulating supply as fallback min. 1 bip less than 1% of min day 1 allocations
            uint256 minBootstrapSnapshot = circulatingSupply * 8 / 10000;
            uint256 onePct = Math.mulDiv(amount, MIN_ALLOCATION_BPS, 10000, Math.Rounding.Floor);
            uint256 pctOrFull = onePct == 0 ? amount : onePct;

            uint256 withFloor = pctOrFull > minBootstrapSnapshot ? pctOrFull : minBootstrapSnapshot;
            allocationValueToStore = withFloor > amount ? amount : withFloor;
        }
    }

    function getKvcmAllocationRateLimiter(address carbonClass)
        internal
        view
        returns (AssetManagerStorage.RateLimiter memory)
    {
        return AssetManagerStorage.classQuoterLayout().quoters[classQuoter(carbonClass)].kvcmAllocationRateLimiter;
    }

    function getK2AllocationRateLimiter(address carbonClass)
        internal
        view
        returns (AssetManagerStorage.RateLimiter memory)
    {
        return AssetManagerStorage.classQuoterLayout().quoters[classQuoter(carbonClass)].k2AllocationRateLimiter;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Rate limiting helpers                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev calculate the effective allocations for the Kvcm and K2 classes
     * @param carbonClass The carbon class
     * @param kvcmStake The kvcm stake
     * @param k2Stake The k2 stake
     * @param currentTimestamp The current timestamp
     * @return kvcmAllocationValueForQuote The effective kvcm stake
     * @return k2AllocationValueForQuote The effective k2 stake
     */
    function calculateAllocationValuesForSwapQuote(
        address carbonClass,
        uint256 kvcmStake,
        uint256 k2Stake,
        uint256 currentTimestamp
    ) internal view returns (uint256 kvcmAllocationValueForQuote, uint256 k2AllocationValueForQuote) {
        uint256 currentEffectiveKvcmAllocation = calculateCurrentEffectiveKvcmAllocation(carbonClass, currentTimestamp);
        uint256 currentEffectiveK2Allocation = calculateCurrentEffectiveK2Allocation(carbonClass, currentTimestamp);

        /**
         * @dev A nonzero stake with a zero effective allocation means the limiter snapshot was never
         * seeded (0/0) and no minimum effective allocation is set for the class.
         */
        if (kvcmStake > 0 && currentEffectiveKvcmAllocation == 0) {
            revert Errors.UninitializedAllocationRateLimiter(carbonClass);
        }

        kvcmAllocationValueForQuote = Math.min(kvcmStake, currentEffectiveKvcmAllocation);
        k2AllocationValueForQuote = Math.min(k2Stake, currentEffectiveK2Allocation);
    }

    /**
     * @dev calculate the current effective kvcm allocation
     * @param carbonClass The carbon class
     * @param currentTimestamp The current timestamp
     * @return currentEffectiveKvcmAllocation The current effective kvcm stake
     */
    function calculateCurrentEffectiveKvcmAllocation(address carbonClass, uint256 currentTimestamp)
        internal
        view
        returns (uint256 currentEffectiveKvcmAllocation)
    {
        AssetManagerStorage.RateLimiter memory kvcmAllocationRateLimiter = getKvcmAllocationRateLimiter(carbonClass);

        uint64 kvcmAllocationRateLimiterRate = getRateLimiterWithClassAndKvcmDefault(kvcmAllocationRateLimiter.rate);

        uint256 minEffective = getMinEffectiveKvcmAllocation(carbonClass);

        /**
         * @dev snapshots should never be zero as then the math will zero out, unless the minimum effective
         * allocation holds the value up. Zero preTxn values are floored in _allocationValueToStore.
         */
        if (
            kvcmAllocationRateLimiter.snapshotValue == 0 && kvcmAllocationRateLimiter.lastUpdateTimestamp != 0
                && minEffective == 0
        ) {
            revert Errors.ZeroAllocationSnapshotValue();
        }

        currentEffectiveKvcmAllocation = Math.max(
            OperationsMath._computeExponentialGrowth(
                kvcmAllocationRateLimiter.snapshotValue,
                kvcmAllocationRateLimiter.lastUpdateTimestamp,
                kvcmAllocationRateLimiterRate,
                currentTimestamp
            ),
            minEffective
        );
    }

    /**
     * @dev calculate the current effective k2 allocation
     * @param carbonClass The carbon class
     * @param currentTimestamp The current timestamp
     * @return currentEffectiveK2Allocation The current effective k2 stake
     */
    function calculateCurrentEffectiveK2Allocation(address carbonClass, uint256 currentTimestamp)
        internal
        view
        returns (uint256 currentEffectiveK2Allocation)
    {
        AssetManagerStorage.RateLimiter memory k2AllocationRateLimiter = getK2AllocationRateLimiter(carbonClass);

        uint64 k2AllocationRateLimiterRate = getRateLimiterWithK2Default(k2AllocationRateLimiter.rate);

        uint256 minEffective = getMinEffectiveK2Allocation(carbonClass);

        // @dev see calculateCurrentEffectiveKvcmAllocation
        if (
            k2AllocationRateLimiter.snapshotValue == 0 && k2AllocationRateLimiter.lastUpdateTimestamp != 0
                && minEffective == 0
        ) {
            revert Errors.ZeroAllocationSnapshotValue();
        }

        currentEffectiveK2Allocation = Math.max(
            OperationsMath._computeExponentialGrowth(
                k2AllocationRateLimiter.snapshotValue,
                k2AllocationRateLimiter.lastUpdateTimestamp,
                k2AllocationRateLimiterRate,
                currentTimestamp
            ),
            minEffective
        );
    }

    /**
     * @dev calculate the effective class balance for the carbon class
     * @param carbonClass The carbon class
     * @param currentTimestamp The current timestamp
     * @return classLiquidSupplyForQuote The effective class liquid supply
     */
    function calculateClassLiquidSupplyForQuote(address carbonClass, uint256 supplyValue, uint256 currentTimestamp)
        internal
        view
        returns (uint256 classLiquidSupplyForQuote)
    {
        uint256 currentEffectiveClassLiquidSupply =
            calculateCurrentEffectiveClassLiquidSupply(carbonClass, currentTimestamp);

        classLiquidSupplyForQuote = Math.max(supplyValue, currentEffectiveClassLiquidSupply);
    }

    /**
     * @dev calculate the current effective class liquid supply
     * @param carbonClass The carbon class
     * @param currentTimestamp The current timestamp
     * @return currentEffectiveClassLiquidSupply The current effective class liquid supply
     */
    function calculateCurrentEffectiveClassLiquidSupply(address carbonClass, uint256 currentTimestamp)
        internal
        view
        returns (uint256 currentEffectiveClassLiquidSupply)
    {
        AssetManagerStorage.RateLimiter memory rateLimiter = getLiquidSupplyRateLimiter(carbonClass);

        uint64 classBalanceRateLimiterRate = getRateLimiterWithClassAndKvcmDefault(rateLimiter.rate);

        currentEffectiveClassLiquidSupply = OperationsMath._computeExponentialDecay(
            rateLimiter.snapshotValue, rateLimiter.lastUpdateTimestamp, classBalanceRateLimiterRate, currentTimestamp
        );
    }

    function getRateLimiterWithClassAndKvcmDefault(uint64 rateInput) internal view returns (uint64 rate) {
        if (rateInput != 0) {
            return rateInput;
        }

        return getDefaultKVCMRate();
    }

    function getRateLimiterWithK2Default(uint64 rateInput) internal view returns (uint64 rate) {
        if (rateInput != 0) {
            return rateInput;
        }

        return getDefaultK2Rate();
    }

    function getRateLimiterSnapshotValues(address carbonClass)
        internal
        view
        returns (RateLimiterSnapshotValues memory)
    {
        AssetManagerStorage.ClassQuoterLayout storage quoterLayout = AssetManagerStorage.classQuoterLayout();
        AssetManagerStorage.ClassQuoterData storage classQuoterData = quoterLayout.quoters[classQuoter(carbonClass)];

        return RateLimiterSnapshotValues({
            liquidSupplySnapshot: classQuoterData.liquidSupplyRateLimiter.snapshotValue,
            kvcmAllocationSnapshot: classQuoterData.kvcmAllocationRateLimiter.snapshotValue,
            k2AllocationSnapshot: classQuoterData.k2AllocationRateLimiter.snapshotValue
        });
    }

    function classQuoter(address carbonClass) internal view returns (address) {
        address quoter = AssetManagerStorage.classQuoterLayout().classToQuoter[carbonClass];
        if (quoter == address(0)) revert Errors.NoQuoterForClass(carbonClass);
        return quoter;
    }
}
