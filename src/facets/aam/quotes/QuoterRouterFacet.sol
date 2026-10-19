// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// interfaces
import "../../../interfaces/ICarbonClassVault.sol";
import "../../../interfaces/AssetManager/IQuoterManager.sol";
import "../../../interfaces/AssetManager/ICarbonClassQuoter.sol";
import "../../../interfaces/IMaturityManager.sol";
import "../../../interfaces/AssetManager/IQuoterRouterFacet.sol";
import "../../../interfaces/ICarbonLedger.sol";
import {IRewardManager} from "../../../interfaces/RewardManager/IRewardManager.sol";
import {IRewardManagerViewFacet} from "../../../interfaces/RewardManager/IRewardManagerViewFacet.sol";
import {IStakingManagerViewFacet} from "../../../interfaces/StakingManager/IStakingManagerViewFacet.sol";
import {IProtocolSupplyOracle} from "../../../interfaces/IProtocolSupplyOracle.sol";
// libraries
import "../../../libraries/storage/AssetManagerStorage.sol";
import "../../../libraries/ValidationLib.sol";
import "../../../libraries/LibDiamond.sol";
import "../../../libraries/Errors.sol";
import {RateLimiterLib} from "../../../libraries/aam/RateLimiterLib.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Constants} from "../../../libraries/Constants.sol";
import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/**
 * @title QuoterRouterFacet
 * @dev Routes quote requests to the appropriate quoter facet based on the carbon class
 */
contract QuoterRouterFacet is IQuoterRouterFacet {
    uint256 public constant DISCOUNT_FACTOR_FALLBACK_LENGTH = 7;

    enum QuoteType {
        SWAP,
        RETIRE
    }

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert NotAuthorized();
        _;
    }

    modifier whenNotPaused() {
        if (AssetManagerStorage.configLayout().systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    /**
     * @dev Get a quote for swapping carbon credits to KVCM
     * @param carbonClass The carbon class to quote
     * @param amount The amount of carbon credits to quote
     * @param maturityId The maturity ID of the carbon credit
     * @return tonnes The amount of carbon credits in tonnes
     * @return price The price quote for the specified amount
     */
    function getSwapQuote(
        address carbonClass,
        address credit,
        uint256 tokenId,
        uint256 amount,
        uint256 maturityId,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        whenNotPaused
        returns (
            uint256 tonnes,
            uint256 price,
            bool isLiquidSwap,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext
        )
    {
        // Get the quoter from the QuoterManagerFacet
        address quoter = IQuoterManager(address(this)).getQuoterForClass(carbonClass);
        if (quoter == address(0)) revert NoQuoterForClass(carbonClass);

        AssetManagerStorage.AssetManagerConfigLayout storage config = AssetManagerStorage.configLayout();

        uint256 kvcmCirculatingSupply = IProtocolSupplyOracle(config.aamConfig.protocolSupplyOracle).getKvcmSupply();
        uint256 k2CirculatingSupply = IProtocolSupplyOracle(config.aamConfig.protocolSupplyOracle).getK2Supply();

        // Liquid if less maturity than first active maturityId
        isLiquidSwap = maturityId < IMaturityManager(config.aamConfig.maturityManager).getFirstActiveMaturityId();

        ClassBalanceContext memory classBalanceContext =
            _resolveClassBalanceContext(isLiquidSwap, carbonClass, maturityId);

        ICarbonClassQuoter.QuoteSwapParams memory swapQuoteParams = ICarbonClassQuoter.QuoteSwapParams({
            isLiquidSwap: isLiquidSwap,
            carbonLedger: config.aamConfig.carbonLedger,
            maturityManager: config.aamConfig.maturityManager,
            carbonClass: carbonClass,
            credit: credit,
            tokenId: tokenId,
            maturityId: maturityId,
            systemPaused: config.systemPaused,
            kvcmCirculatingSupply: kvcmCirculatingSupply,
            classBalanceContext: classBalanceContext,
            classValuesForSwapQuote: _getClassValuesForSwapQuote(
                carbonClass,
                config.aamConfig.stakingManager,
                kvcmCirculatingSupply,
                k2CirculatingSupply,
                classBalanceContext.activeMaturities,
                classBalanceContext.discountForwardBalanceInitializedForDay,
                classBalanceContext.discountFactors
            )
        });

        uint256 discountedForwardBalanceForCurrentMidnightIndex;
        uint256 amountUsedForSwapQuote;

        //@dev the facet itself will revert an unregistered credit
        (tonnes, price, isLiquidSwap, amountUsedForSwapQuote, discountedForwardBalanceForCurrentMidnightIndex) =
            ICarbonClassQuoter(quoter).quoteSwap(amount, swapQuoteParams, couponBurnParams);

        // if no coupon is being used, tonnes should always be non-zero
        if (tonnes == 0 && couponBurnParams.tonnes == 0) revert Errors.InvalidAmountTooSmall(tonnes);

        discountedForwardBalanceContext = IQuoterRouterFacet.DiscountedForwardBalanceContext({
            currentMidnightIndex: classBalanceContext.currentMidnightIndex,
            amountUsedForSwapQuote: amountUsedForSwapQuote,
            discountedForwardBalanceForCurrentMidnightIndex: discountedForwardBalanceForCurrentMidnightIndex
        });
    }

    /**
     * @dev Get a quote for retiring a specific carbon credit
     * @param carbonClass The carbon class of the token
     * @param tokenId The token ID
     * @param amount The amount of carbon credits to quote
     * @return tonnes The amount of carbon credits in tonnes
     * @return kvcmRetirementPrice The price quote for the specified amount
     */

    function getRetirementQuote(
        address carbonClass,
        address credit,
        uint256 tokenId,
        uint256 amount,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        whenNotPaused
        returns (
            uint256 tonnes,
            uint256 kvcmRetirementPrice,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext,
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory updateLiquidSupplyRateLimiterParams
        )
    {
        // Get the quoter from the QuoterManagerFacet
        address quoter = IQuoterManager(address(this)).getQuoterForClass(carbonClass);

        if (quoter == address(0)) revert NoQuoterForClass(carbonClass);

        // need to get all addresses and system state
        AssetManagerStorage.AssetManagerConfigLayout storage config = AssetManagerStorage.configLayout();

        uint256 kvcmCirculatingSupply = IProtocolSupplyOracle(config.aamConfig.protocolSupplyOracle).getKvcmSupply();

        uint256 k2CirculatingSupply = IProtocolSupplyOracle(config.aamConfig.protocolSupplyOracle).getK2Supply();

        ClassBalanceContext memory classBalanceContext = _resolveClassBalanceContext(true, carbonClass, 0);

        uint256 discountedForwardBalanceForCurrentMidnightIndex;
        uint256 preTxnLiquidSupply;
        {
            ICarbonClassQuoter.QuoteRetirementParams memory retirementParams = ICarbonClassQuoter.QuoteRetirementParams({
                carbonLedger: config.aamConfig.carbonLedger,
                carbonClass: carbonClass,
                credit: credit,
                tokenId: tokenId,
                systemPaused: config.systemPaused,
                kvcmCirculatingSupply: kvcmCirculatingSupply,
                classBalanceContext: classBalanceContext,
                classValuesForRetireQuote: _getClassValuesForRetireQuote(
                    carbonClass,
                    config.aamConfig.stakingManager,
                    kvcmCirculatingSupply,
                    k2CirculatingSupply,
                    classBalanceContext.activeMaturities,
                    classBalanceContext.discountFactors
                )
            });

            (tonnes, kvcmRetirementPrice, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply) =
                ICarbonClassQuoter(quoter).quoteRetirement(address(this), amount, retirementParams, couponBurnParams);

            // if no coupon is being used, tonnes should always be non-zero
            if (tonnes == 0 && couponBurnParams.tonnes == 0) revert Errors.InvalidAmountTooSmall(tonnes);
        }

        updateLiquidSupplyRateLimiterParams =
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams({preTxnLiquidSupply: preTxnLiquidSupply});

        discountedForwardBalanceContext = IQuoterRouterFacet.DiscountedForwardBalanceContext({
            currentMidnightIndex: classBalanceContext.currentMidnightIndex,
            // @deb no discount for liquid retirement tonnes --> pass straight value
            amountUsedForSwapQuote: tonnes,
            discountedForwardBalanceForCurrentMidnightIndex: discountedForwardBalanceForCurrentMidnightIndex
        });
    }

    /**
     * @dev Inverse retirement quote: given a kVCM budget, return tonnes retired of a specific class
     * @param carbonClass The carbon class of the token
     * @param credit The carbon credit token address
     * @param tokenId The token ID
     * @param kvcmIn The kVCM budget to spend on retirement
     * @param couponBurnParams Parameters for burning coupons during retirement
     */
    function getRetirementQuoteForKvcmIn(
        address carbonClass,
        address credit,
        uint256 tokenId,
        uint256 kvcmIn,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        whenNotPaused
        returns (
            uint256 tonnes,
            uint256 tokenAmount,
            uint256 kvcmRetirementPrice,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext,
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory updateLiquidSupplyRateLimiterParams
        )
    {
        address quoter = IQuoterManager(address(this)).getQuoterForClass(carbonClass);
        if (quoter == address(0)) revert NoQuoterForClass(carbonClass);

        AssetManagerStorage.AssetManagerConfigLayout storage config = AssetManagerStorage.configLayout();

        uint256 kvcmCirculatingSupply = IProtocolSupplyOracle(config.aamConfig.protocolSupplyOracle).getKvcmSupply();
        uint256 k2CirculatingSupply = IProtocolSupplyOracle(config.aamConfig.protocolSupplyOracle).getK2Supply();

        ClassBalanceContext memory classBalanceContext = _resolveClassBalanceContext(true, carbonClass, 0);

        uint256 discountedForwardBalanceForCurrentMidnightIndex;
        uint256 preTxnLiquidSupply;
        {
            ICarbonClassQuoter.QuoteRetirementParams memory retirementParams = ICarbonClassQuoter.QuoteRetirementParams({
                carbonLedger: config.aamConfig.carbonLedger,
                carbonClass: carbonClass,
                credit: credit,
                tokenId: tokenId,
                systemPaused: config.systemPaused,
                kvcmCirculatingSupply: kvcmCirculatingSupply,
                classBalanceContext: classBalanceContext,
                classValuesForRetireQuote: _getClassValuesForRetireQuote(
                    carbonClass,
                    config.aamConfig.stakingManager,
                    kvcmCirculatingSupply,
                    k2CirculatingSupply,
                    classBalanceContext.activeMaturities,
                    classBalanceContext.discountFactors
                )
            });

            (
                tonnes,
                tokenAmount,
                kvcmRetirementPrice,
                discountedForwardBalanceForCurrentMidnightIndex,
                preTxnLiquidSupply
            ) =
                ICarbonClassQuoter(quoter)
                    .quoteRetirementForKvcmIn(address(this), kvcmIn, retirementParams, couponBurnParams);
        }

        updateLiquidSupplyRateLimiterParams =
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams({preTxnLiquidSupply: preTxnLiquidSupply});

        discountedForwardBalanceContext = IQuoterRouterFacet.DiscountedForwardBalanceContext({
            currentMidnightIndex: classBalanceContext.currentMidnightIndex,
            amountUsedForSwapQuote: tonnes,
            discountedForwardBalanceForCurrentMidnightIndex: discountedForwardBalanceForCurrentMidnightIndex
        });
    }

    function getClassForQuoter(address quoter) external view returns (address) {
        return AssetManagerStorage.classQuoterLayout().quoterToClass[quoter];
    }

    function getDiscountedForwardBalanceRecordForIndex(uint256 midnightIndex, address carbonClass)
        external
        view
        returns (bool initialized, uint256 storedBaseline)
    {
        AssetManagerStorage.ClassQuoterLayout storage l = AssetManagerStorage.classQuoterLayout();
        AssetManagerStorage.DiscountedForwardBalanceIndexRecord storage r =
            l.discountedForwardBalancesForCurrentMidnightIndex[midnightIndex][carbonClass];
        return (r.discountForwardBalanceInitializedForDay, r.discountedForwardBalanceForCurrentMidnightIndex);
    }

    /*--------------------------------------------------------*/
    /* Internal Functions */
    /*--------------------------------------------------------*/

    function _getClassValuesForSwapQuote(
        address carbonClass,
        address stakingManager,
        uint256 kvcmCirculatingSupply,
        uint256 k2CirculatingSupply,
        uint256[] memory activeMaturities,
        bool discountForwardBalanceInitializedForDay,
        IRewardManager.MaturityDiscountFactor[] memory discountFactors
    ) internal view returns (IQuoterRouterFacet.ClassValuesForQuote memory classValuesForSwapQuote) {
        /* pull vault tonnage data */
        (uint256 totalTonnes, uint256 liquidTonnes, CommonStructs.MaturityTonnes[] memory maturitiesTonnes) =
            _getVaultTonnageData(carbonClass, activeMaturities, discountForwardBalanceInitializedForDay);

        if (!discountForwardBalanceInitializedForDay && maturitiesTonnes.length != discountFactors.length) {
            revert Errors.ActiveMaturityLengthMismatch(maturitiesTonnes.length, discountFactors.length);
        }

        uint256 rateLimitedLiquidSupply =
            RateLimiterLib.calculateClassLiquidSupplyForQuote(carbonClass, liquidTonnes, block.timestamp);

        (uint256 normalizedKvcmClassAllocation, uint256 normalizedK2ClassAllocation) = _getNormalizedClassAllocationsForQuote(
            QuoteType.SWAP, carbonClass, stakingManager, kvcmCirculatingSupply, k2CirculatingSupply, block.timestamp
        );

        classValuesForSwapQuote = IQuoterRouterFacet.ClassValuesForQuote({
            normalizedKvcmClassAllocation: normalizedKvcmClassAllocation,
            normalizedK2ClassAllocation: normalizedK2ClassAllocation,
            totalTonnes: totalTonnes,
            liquidSupplyForQuote: rateLimitedLiquidSupply,
            maturitiesTonnes: maturitiesTonnes
        });

        return classValuesForSwapQuote;
    }

    function _getClassValuesForRetireQuote(
        address carbonClass,
        address stakingManager,
        uint256 kvcmCirculatingSupply,
        uint256 k2CirculatingSupply,
        uint256[] memory activeMaturities,
        IRewardManager.MaturityDiscountFactor[] memory discountFactors
    ) internal view returns (IQuoterRouterFacet.ClassValuesForQuote memory classValuesForRetireQuote) {
        /* pull vault tonnage data */
        (uint256 totalTonnes, uint256 liquidTonnes, CommonStructs.MaturityTonnes[] memory maturitiesTonnes) =
            _getVaultTonnageData(carbonClass, activeMaturities, false);

        if (maturitiesTonnes.length != discountFactors.length) {
            revert Errors.ActiveMaturityLengthMismatch(maturitiesTonnes.length, discountFactors.length);
        }

        (uint256 normalizedKvcmClassAllocation, uint256 normalizedK2ClassAllocation) = _getNormalizedClassAllocationsForQuote(
            QuoteType.RETIRE, carbonClass, stakingManager, kvcmCirculatingSupply, k2CirculatingSupply, block.timestamp
        );

        classValuesForRetireQuote = IQuoterRouterFacet.ClassValuesForQuote({
            normalizedKvcmClassAllocation: normalizedKvcmClassAllocation,
            normalizedK2ClassAllocation: normalizedK2ClassAllocation,
            totalTonnes: totalTonnes,
            liquidSupplyForQuote: liquidTonnes,
            maturitiesTonnes: maturitiesTonnes
        });

        return classValuesForRetireQuote;
    }

    function _getVaultTonnageData(
        address carbonClass,
        uint256[] memory activeMaturities,
        bool discountForwardBalanceInitializedForDay
    )
        internal
        view
        returns (uint256 totalTonnes, uint256 liquidTonnes, CommonStructs.MaturityTonnes[] memory maturitiesTonnes)
    {
        if (discountForwardBalanceInitializedForDay) {
            // let maturitiesTonnes be empty array for this case
            (totalTonnes, liquidTonnes) = ICarbonClassVault(carbonClass).getSelectedVaultTonnes(activeMaturities);
        } else {
            (totalTonnes, liquidTonnes,, maturitiesTonnes) =
                ICarbonClassVault(carbonClass).getVaultTonnes(activeMaturities);
        }
    }

    function _getNormalizedClassAllocationsForQuote(
        QuoteType quoteType,
        address carbonClass,
        address stakingManager,
        uint256 kvcmCirculatingSupply,
        uint256 k2CirculatingSupply,
        uint256 nowTs
    ) internal view returns (uint256 normalizedKvcmClassAllocation, uint256 normalizedK2ClassAllocation) {
        /* pull price stakes. kvcm allocation must !== 0 in order to quote & swap */
        IStakingManagerViewFacet.ClassAllocations memory allocations =
            IStakingManagerViewFacet(stakingManager).getAllocationsForClass(carbonClass);
        /* nonzero kvcm allocation required for any swap or retire */
        if (allocations.kvcmAllocation == 0) revert Errors.ZeroAllocationForClass(carbonClass);

        uint256 kvcmAllocationAmtForQuote;
        uint256 k2AllocationAmtForQuote;

        // @dev check for maturity length <> discount factors length mismatch.
        if (quoteType == QuoteType.SWAP) {
            (uint256 effectiveKvcmStake, uint256 effectiveK2Stake) = RateLimiterLib.calculateAllocationValuesForSwapQuote(
                carbonClass, allocations.kvcmAllocation, allocations.k2Allocation, nowTs
            );
            kvcmAllocationAmtForQuote = effectiveKvcmStake;
            k2AllocationAmtForQuote = effectiveK2Stake;
        } else if (quoteType == QuoteType.RETIRE) {
            kvcmAllocationAmtForQuote = allocations.kvcmAllocation;
            k2AllocationAmtForQuote = allocations.k2Allocation;
        } else {
            revert Errors.InvalidQuoteType();
        }

        /* normalize allocations */
        normalizedKvcmClassAllocation = Math.mulDiv(kvcmAllocationAmtForQuote, Constants.WAD, kvcmCirculatingSupply);
        normalizedK2ClassAllocation =
            k2CirculatingSupply > 0 ? Math.mulDiv(k2AllocationAmtForQuote, Constants.WAD, k2CirculatingSupply) : 0;
    }

    /**
     * @dev Provide relevant data for the class balance context
     * @param carbonClass The carbon class to resolve the context for
     * @return ctx The class balance context
     */
    function _resolveClassBalanceContext(bool isLiquidSwap, address carbonClass, uint256 maturityId)
        internal
        view
        returns (ClassBalanceContext memory ctx)
    {
        AssetManagerStorage.AssetManagerConfigLayout storage config = AssetManagerStorage.configLayout();
        AssetManagerStorage.ClassQuoterLayout storage classQuoterLayout = AssetManagerStorage.classQuoterLayout();

        (uint256 currentMidnightIndex,,,) =
            IMaturityManager(config.aamConfig.maturityManager).getAdjacentMidnightInfo(block.timestamp);

        bool discountForwardBalanceInitializedForDay =
            classQuoterLayout.discountedForwardBalancesForCurrentMidnightIndex[currentMidnightIndex][carbonClass]
            .discountForwardBalanceInitializedForDay;

        uint256 discountedForwardBalanceForCurrentMidnightIndex =
            classQuoterLayout.discountedForwardBalancesForCurrentMidnightIndex[currentMidnightIndex][carbonClass]
            .discountedForwardBalanceForCurrentMidnightIndex;

        // @dev default empty arrays; only fetch DFs if below conditions are met
        IRewardManager.MaturityDiscountFactor[] memory discountFactors = new IRewardManager.MaturityDiscountFactor[](0);
        uint256[] memory activeMaturities = new uint256[](0);

        // on the first run we need need the active maturities and discount factors to create the discounted forward balance
        if (!discountForwardBalanceInitializedForDay) {
            (discountFactors, activeMaturities) =
                _getDiscountFactorsWithFallback(currentMidnightIndex, config.aamConfig.rewardManager);
        }

        // @dev no stored df --> no forward swap; the quoter's zero-baseline early return skips its own df check
        // nothing stores dfs yet (no RollUpdateFacet writer): every forward swap reverts until one is added
        if (!isLiquidSwap && discountForwardBalanceInitializedForDay) {
            discountFactors = new IRewardManager.MaturityDiscountFactor[](1);
            uint256 discountFactor = IRewardManagerViewFacet(config.aamConfig.rewardManager)
                .getDiscountFactor(currentMidnightIndex, maturityId);
            // @dev no stored discount factor --> no forward swap. this will disable fwds until we add a writer to RollUpdateFacet
            if (discountFactor == 0) revert Errors.NoDiscountFactorForMaturity(maturityId);
            discountFactors[0] = IRewardManager.MaturityDiscountFactor({
                maturityId: maturityId, discountFactor: SafeCast.toUint64(discountFactor)
            });
        }

        ctx = ClassBalanceContext({
            currentMidnightIndex: currentMidnightIndex,
            discountForwardBalanceInitializedForDay: discountForwardBalanceInitializedForDay,
            discountedForwardBalanceForCurrentMidnightIndex: discountedForwardBalanceForCurrentMidnightIndex,
            discountFactors: discountFactors,
            activeMaturities: activeMaturities
        });
    }

    function _getDiscountFactorsWithFallback(uint256 currentMidnightIndex, address rewardManager)
        internal
        view
        returns (IRewardManager.MaturityDiscountFactor[] memory discountFactors, uint256[] memory activeMaturities)
    {
        // try current midnight index (most recent past midnight)
        (discountFactors, activeMaturities) = IRewardManager(rewardManager).getDiscountFactors(currentMidnightIndex);

        // returns true if array non-empty and both ends are non-zero
        if (_dfsEndsNonZero(discountFactors)) {
            return (discountFactors, activeMaturities);
        }

        // fallback: walk back up to N days, starting at previous day (i = 1)
        uint256 limit = DISCOUNT_FACTOR_FALLBACK_LENGTH;
        // cap the loop if currentMidnightIndex is small to avoid underflow
        if (currentMidnightIndex < limit) limit = currentMidnightIndex;

        for (uint256 i = 1; i <= limit;) {
            (discountFactors, activeMaturities) =
                IRewardManager(rewardManager).getDiscountFactors(currentMidnightIndex - i);
            if (_dfsEndsNonZero(discountFactors)) {
                return (discountFactors, activeMaturities);
            }
            unchecked {
                ++i;
            }
        }

        // 3) Still no usable dfs: return empty arrays to trigger total tonnage fallback in BaseCarbonClassQuoterFacet
        return (new IRewardManager.MaturityDiscountFactor[](0), new uint256[](0));
    }
    /*--------------------------------------------------------*/
    /* Pure Functions */
    /*--------------------------------------------------------*/

    function _dfsEndsNonZero(IRewardManager.MaturityDiscountFactor[] memory dfs) private pure returns (bool) {
        uint256 len = dfs.length;
        if (len == 0) return false; // if no discount factors, return false

        return (dfs[0].discountFactor | dfs[len - 1].discountFactor) != 0; // if first or last discount factor is not zero, return true
    }
}
