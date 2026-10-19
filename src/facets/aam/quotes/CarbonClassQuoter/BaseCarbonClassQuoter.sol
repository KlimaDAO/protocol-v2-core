// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// interfaces
import "src/interfaces/AssetManager/ICarbonClassQuoter.sol";
import "src/interfaces/ICarbonClassVault.sol";
import "src/interfaces/ICarbonLedger.sol";
import "src/interfaces/IMaturityManager.sol";
// libraries
import "src/libraries/LibDiamond.sol";
import "src/libraries/Errors.sol";
import "src/libraries/aam/OperationsMath.sol";
import "src/libraries/ValidationLib.sol";
import "src/libraries/Constants.sol";
// facets
import "src/facets/aam/quotes/QuoterRouterFacet.sol";
import {IQuoterRouterFacet} from "src/interfaces/AssetManager/IQuoterRouterFacet.sol";

// oz libraries
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BaseCarbonClassQuoter
 * @dev base class for carbon class quoter facets
 * Specific carbon class quoter facets should inherit from this class
 */
contract BaseCarbonClassQuoter is ICarbonClassQuoter {
    using Math for uint256;

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert Errors.NotAuthorized();
        _;
    }

    modifier whenNotPaused(bool systemPaused) {
        if (systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    /**
     * @dev Quote the price for swapping carbon credits to KVCM
     * @param amount The amount of carbon credits to quote
     * @param params The parameters for the swap quote
     * @param couponBurnParams The parameters for the coupon burn
     * @return tonnes The amount of carbon credits in tonnes
     * @return kvcmPrice The price quote for the specified swap
     * @return isLiquidSwap True if the swap is liquid, false otherwise
     *
     */
    function quoteSwap(
        uint256 amount,
        ICarbonClassQuoter.QuoteSwapParams calldata params,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        virtual
        returns (
            uint256 tonnes,
            uint256 kvcmPrice,
            bool isLiquidSwap,
            uint256 amountUsedForSwapQuote,
            uint256 discountedForwardBalanceForCurrentMidnightIndex
        )
    {
        if (couponBurnParams.tonnes > 0) {
            ValidationLib.validateCoupon(
                couponBurnParams.tonnes, IERC20(params.carbonClass).balanceOf(couponBurnParams.from)
            );
        }

        ValidationLib.validateRegistration(
            ICarbonLedger(params.carbonLedger), ICarbonClassVault(params.carbonClass), params.credit, params.tokenId
        );

        tonnes = ICarbonClassVault(params.carbonClass).convertTokenAmountToTonnes(amount, params.credit, params.tokenId);

        ValidationLib.validateAmount(tonnes + couponBurnParams.tonnes);

        uint256 totalTonnesToQuote = tonnes + couponBurnParams.tonnes;

        (kvcmPrice, isLiquidSwap, amountUsedForSwapQuote, discountedForwardBalanceForCurrentMidnightIndex) =
            _quoteSwap(totalTonnesToQuote, params);
    }

    function _quoteSwap(uint256 amount, ICarbonClassQuoter.QuoteSwapParams calldata params)
        internal
        view
        returns (
            uint256 kvcmPrice,
            bool isLiquidSwap,
            uint256 amountUsedForSwapQuote,
            uint256 discountedForwardBalanceForCurrentMidnightIndex
        )
    {
        // interfaces
        IMaturityManager maturityManager = IMaturityManager(params.maturityManager);
        bool _isLiquidSwap = params.isLiquidSwap;

        // @dev using activeMaturities[0] will not work as if no dfs for past seven days are found we pass an empty array.  liquid swaps are valid, forwards are not.

        uint256 targetMaturityId = _isLiquidSwap ? 0 : params.maturityId;

        // verify maturity validity
        if (!_isLiquidSwap && !maturityManager.isValidMaturityId(targetMaturityId)) {
            revert Errors.InvalidMaturityId(targetMaturityId);
        }

        (
            uint256 normalizedKvcmClassAllocation,
            uint256 normalizedK2ClassAllocation,
            uint256 totalTonnes,
            uint256 rateLimitedLiquidSupply,
            CommonStructs.MaturityTonnes[] memory maturitiesTonnes
        ) = unpackClassValuesForQuote(params.classValuesForSwapQuote);
        (
            uint256 currentMidnightIndex,
            bool discountForwardBalanceInitializedForDay,
            uint256 _discountedForwardBalanceForCurrentMidnightIndex,
            IRewardManager.MaturityDiscountFactor[] memory discountFactors,
        ) = unpackClassBalanceContext(params.classBalanceContext);

        uint256 totalAmountForQuote;

        bool foundMaturity = _isLiquidSwap;

        if (_isLiquidSwap) {
            totalAmountForQuote = amount;
        }
        // If no tonnage, use zero carbon scenario and bypass discounted forwards calculation
        if (totalTonnes == 0) {
            /* zero carbon scenario */
            // @dev _calculateDiscountedDelta will revert if discount factor doesn't exist i.e. if most recent trigger has not run
            totalAmountForQuote = _isLiquidSwap
                ? amount
                : OperationsMath.calculateDiscountedDelta(
                    amount, _findDiscountFactor(discountFactors, targetMaturityId)
                );

            uint256 deltaA = OperationsMath.calculateKvcmSwapDeltaZeroCarbonScenario(
                totalAmountForQuote, normalizedKvcmClassAllocation, normalizedK2ClassAllocation
            );

            kvcmPrice = Math.mulDiv(deltaA, params.kvcmCirculatingSupply, Constants.WAD);

            return (kvcmPrice, _isLiquidSwap, totalAmountForQuote, 0);
        } else {
            /* postive vault tonnage carbon scenario */
            (totalAmountForQuote, discountedForwardBalanceForCurrentMidnightIndex, foundMaturity) =
                _resolveClassBalancePaths(
                    ClassBalancePathsParams({
                        amount: amount,
                        targetMaturityId: targetMaturityId,
                        isLiquidSwap: _isLiquidSwap,
                        isRetirement: false,
                        maturitiesTonnes: maturitiesTonnes,
                        discountForwardBalanceInitializedForDay: discountForwardBalanceInitializedForDay,
                        discountedForwardBalanceForCurrentMidnightIndex: _discountedForwardBalanceForCurrentMidnightIndex,
                        discountFactors: discountFactors,
                        totalTonnes: totalTonnes,
                        liquidSupplyForQuote: rateLimitedLiquidSupply
                    })
                );
        }

        if (!foundMaturity) {
            revert Errors.InvalidMaturityId(targetMaturityId);
        }

        /* calculate effective total vault balance for quote after including discounted forwards & rate limited liquid supply */
        uint256 classSupplyForQuote = rateLimitedLiquidSupply + discountedForwardBalanceForCurrentMidnightIndex;

        kvcmPrice = OperationsMath.calculateSwapKvcmPrice(
            classSupplyForQuote,
            totalAmountForQuote,
            normalizedKvcmClassAllocation,
            normalizedK2ClassAllocation,
            params.kvcmCirculatingSupply
        );

        return (kvcmPrice, _isLiquidSwap, totalAmountForQuote, discountedForwardBalanceForCurrentMidnightIndex);
    }

    function quoteRetirement(
        address aam,
        uint256 amount,
        ICarbonClassQuoter.QuoteRetirementParams calldata params,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        returns (
            uint256 tonnes,
            uint256 retirementKvcmQuote,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            uint256 preTxnLiquidSupply
        )
    {
        if (couponBurnParams.tonnes > 0) {
            ValidationLib.validateCoupon(
                couponBurnParams.tonnes, IERC20(params.carbonClass).balanceOf(couponBurnParams.from)
            );
        }

        ValidationLib.validateRegistration(
            ICarbonLedger(params.carbonLedger), ICarbonClassVault(params.carbonClass), params.credit, params.tokenId
        );

        tonnes = ICarbonClassVault(params.carbonClass).convertTokenAmountToTonnes(amount, params.credit, params.tokenId);

        ValidationLib.validateAmount(tonnes + couponBurnParams.tonnes);
        uint256 netTonnesToQuote = (couponBurnParams.tonnes >= tonnes) ? 0 : tonnes - couponBurnParams.tonnes;

        /**
         * @dev with coupon redemption the adjusted quote amount can be < min tonnes
         */
        (retirementKvcmQuote, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply) =
            _quoteRetirement(aam, netTonnesToQuote, params);

        // if coupon covers (or over-covers) the whole retirement ⇒ free
        if (couponBurnParams.tonnes >= tonnes) {
            // coupon covers (or over-covers) the whole retirement ⇒ free
            return (tonnes, 0, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply);
        }

        return (tonnes, retirementKvcmQuote, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply);
    }

    function quoteRetirementForKvcmIn(
        address aam,
        uint256 kvcmIn,
        ICarbonClassQuoter.QuoteRetirementParams calldata params,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        returns (
            uint256 tonnes,
            uint256 tokenAmount,
            uint256 retirementKvcmQuote,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            uint256 preTxnLiquidSupply
        )
    {
        if (couponBurnParams.tonnes > 0) {
            ValidationLib.validateCoupon(
                couponBurnParams.tonnes, IERC20(params.carbonClass).balanceOf(couponBurnParams.from)
            );
        }

        ValidationLib.validateRegistration(
            ICarbonLedger(params.carbonLedger), ICarbonClassVault(params.carbonClass), params.credit, params.tokenId
        );

        uint256 netTonnesFromBudget;
        (netTonnesFromBudget, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply) =
            _quoteRetirementForKvcmIn(aam, kvcmIn, params);

        uint256 classBalanceForQuote = preTxnLiquidSupply + discountedForwardBalanceForCurrentMidnightIndex;

        uint256 retirableNetTonnes;
        (tokenAmount, retirableNetTonnes, retirementKvcmQuote) =
            _quoteRetirableTonnes(netTonnesFromBudget, classBalanceForQuote, params);

        // PROBLEM: the amount we just derived from the budget can cost slightly MORE than the budget.
        // Budget -> tonnes, then tonnes -> price, and each direction rounds on its own, so the two
        // do not always land on the same number. In practice this happens when the budget buys nearly the
        // whole class balance.
        //
        // WHY WE CAN'T JUST REPORT `kvcmIn` AS THE PRICE: on retire, the AAM prices `tokenAmount` again by
        // itself and pulls that much kVCM. Callers approve exactly the price returned here, so if we report
        // less than the AAM will charge, the retirement reverts.
        //
        // FIX: retire slightly fewer tonnes and price again, until the price fits the budget. What we return
        // is then always the real price of the real amount.
        //
        // STEP SIZE: the quote cannot see a change smaller than (class balance / 1e18) tonnes, so that is the
        // smallest step that can move the price. One step is normally enough. It doubles each pass so the loop
        // always ends: at worst it reaches zero tonnes, which costs nothing.
        uint256 tonnesStep = Math.max(1, Math.ceilDiv(classBalanceForQuote, Constants.WAD));
        while (retirementKvcmQuote > kvcmIn) {
            (tokenAmount, retirableNetTonnes, retirementKvcmQuote) = _quoteRetirableTonnes(
                retirableNetTonnes > tonnesStep ? retirableNetTonnes - tonnesStep : 0, classBalanceForQuote, params
            );
            tonnesStep *= 2;
        }

        tonnes = retirableNetTonnes + couponBurnParams.tonnes;

        if (retirableNetTonnes == 0) {
            // budget too small to back a whole token unit (or coupon-only / zero-budget): no kvcm cost
            return (tonnes, 0, 0, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply);
        }

        if (retirementKvcmQuote >= params.kvcmCirculatingSupply) revert Errors.CannotRetireEntireKvcmSupply();
    }

    /**
     * @dev Given tonnes to retire, return the token amount to pass to the retire entrypoint and the kVCM it will cost
     * @param netTonnes The net (coupon-exclusive) tonnes to retire
     * @param classBalanceForQuote The class balance the quote is priced against (liquid supply + discounted forwards)
     * @param params The parameters for the retirement quote
     * @return tokenAmount The credit token amount for `netTonnes`, rounded down
     * @return retirableNetTonnes The tonnes `tokenAmount` is actually worth (can be slightly below `netTonnes`)
     * @return retirementKvcmQuote The kVCM price of retiring `tokenAmount`
     */
    function _quoteRetirableTonnes(
        uint256 netTonnes,
        uint256 classBalanceForQuote,
        ICarbonClassQuoter.QuoteRetirementParams calldata params
    ) internal view returns (uint256 tokenAmount, uint256 retirableNetTonnes, uint256 retirementKvcmQuote) {
        // **IMPORTANT** The retire entrypoint takes a TOKEN amount, not tonnes. It works out the tonnes, and
        // therefore the price, from that token amount itself.
        //
        // Converting tonnes to tokens rounds down for credits where 1 token is not 1 tonne, so the tokens we can
        // actually hand over may be worth slightly fewer tonnes than we asked for.
        //
        // So: convert tonnes -> tokens, convert those tokens back -> tonnes, and price that amount. It is the same
        // tonnage the AAM computes on retire, which keeps this price identical to what it charges. The
        // active-lock flow requires them to match exactly and reverts otherwise.
        tokenAmount =
            ICarbonClassVault(params.carbonClass).convertTonnesToTokenAmount(netTonnes, params.credit, params.tokenId);
        retirableNetTonnes = ICarbonClassVault(params.carbonClass)
            .convertTokenAmountToTonnes(tokenAmount, params.credit, params.tokenId);

        if (retirableNetTonnes == 0) {
            return (0, 0, 0);
        }

        retirementKvcmQuote = OperationsMath.calculateKvcmRetirementQuote(
            retirableNetTonnes,
            params.classValuesForRetireQuote.normalizedKvcmClassAllocation,
            params.classValuesForRetireQuote.normalizedK2ClassAllocation,
            classBalanceForQuote,
            params.kvcmCirculatingSupply
        );
    }

    function _quoteRetirementForKvcmIn(
        address aam,
        uint256 kvcmIn,
        ICarbonClassQuoter.QuoteRetirementParams calldata params
    )
        internal
        view
        returns (
            uint256 netTonnesFromBudget,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            uint256 preTxnLiquidSupply
        )
    {
        (
            uint256 normalizedKvcmClassAllocation,
            uint256 normalizedK2ClassAllocation,
            uint256 totalTonnes,
            uint256 rawLiquidSupply,
            CommonStructs.MaturityTonnes[] memory maturitiesTonnes
        ) = unpackClassValuesForQuote(params.classValuesForRetireQuote);

        preTxnLiquidSupply = rawLiquidSupply;

        (
            ,
            bool discountForwardBalanceInitializedForDay,
            uint256 _discountedForwardBalanceForCurrentMidnightIndex,
            IRewardManager.MaturityDiscountFactor[] memory discountFactors,
        ) = unpackClassBalanceContext(params.classBalanceContext);

        (, discountedForwardBalanceForCurrentMidnightIndex,) = _resolveClassBalancePaths(
            ClassBalancePathsParams({
                amount: 0,
                targetMaturityId: 0,
                isLiquidSwap: true,
                isRetirement: true,
                maturitiesTonnes: maturitiesTonnes,
                discountForwardBalanceInitializedForDay: discountForwardBalanceInitializedForDay,
                discountedForwardBalanceForCurrentMidnightIndex: _discountedForwardBalanceForCurrentMidnightIndex,
                discountFactors: discountFactors,
                totalTonnes: totalTonnes,
                liquidSupplyForQuote: rawLiquidSupply
            })
        );

        if (kvcmIn == 0) {
            return (0, discountedForwardBalanceForCurrentMidnightIndex, preTxnLiquidSupply);
        }

        netTonnesFromBudget = OperationsMath.calculateTonnesRetirementFromKvcm(
            kvcmIn,
            normalizedKvcmClassAllocation,
            normalizedK2ClassAllocation,
            rawLiquidSupply + discountedForwardBalanceForCurrentMidnightIndex,
            params.kvcmCirculatingSupply
        );

        if (netTonnesFromBudget > rawLiquidSupply) {
            netTonnesFromBudget = rawLiquidSupply;
        }
    }

    /**
     * @dev Quote the price for retiring a specific carbon credit
     * @param aam The address of the AAM
     * @param amount The amount of carbon credits to quote
     * @param preTxnLiquidSupply The liquid supply before the transaction
     * @param params The parameters for the retirement quote
     * @return retirementKvcmQuote The price quote for the specified retirement
     *
     */
    function _quoteRetirement(address aam, uint256 amount, ICarbonClassQuoter.QuoteRetirementParams calldata params)
        internal
        view
        returns (
            uint256 retirementKvcmQuote,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            uint256 preTxnLiquidSupply
        )
    {
        {
            /* validate liquid balance of credit */
            uint256 liquidCreditBalance =
                ICarbonClassVault(params.carbonClass).getLiquidTokenTonnes(params.credit, params.tokenId);
            if (liquidCreditBalance < amount) {
                revert Errors.InsufficientCreditBalance(liquidCreditBalance, amount);
            }
        }

        (
            uint256 normalizedKvcmClassAllocation,
            uint256 normalizedK2ClassAllocation,
            uint256 totalTonnes,
            uint256 rawLiquidSupply,
            CommonStructs.MaturityTonnes[] memory maturitiesTonnes
        ) = unpackClassValuesForQuote(params.classValuesForRetireQuote);

        preTxnLiquidSupply = rawLiquidSupply;

        (
            ,
            bool discountForwardBalanceInitializedForDay,
            uint256 _discountedForwardBalanceForCurrentMidnightIndex,
            IRewardManager.MaturityDiscountFactor[] memory discountFactors,
        ) = unpackClassBalanceContext(params.classBalanceContext);

        (, discountedForwardBalanceForCurrentMidnightIndex,) = _resolveClassBalancePaths(
            ClassBalancePathsParams({
                amount: amount,
                targetMaturityId: 0,
                isLiquidSwap: true,
                isRetirement: true,
                maturitiesTonnes: maturitiesTonnes,
                discountForwardBalanceInitializedForDay: discountForwardBalanceInitializedForDay,
                discountedForwardBalanceForCurrentMidnightIndex: _discountedForwardBalanceForCurrentMidnightIndex,
                discountFactors: discountFactors,
                totalTonnes: totalTonnes,
                liquidSupplyForQuote: rawLiquidSupply
            })
        );
        // }

        {
            /*calculate quote scope*/
            /* raw liquid supply + discounted forwards */
            retirementKvcmQuote = OperationsMath.calculateKvcmRetirementQuote(
                amount,
                normalizedKvcmClassAllocation,
                normalizedK2ClassAllocation,
                rawLiquidSupply + discountedForwardBalanceForCurrentMidnightIndex,
                params.kvcmCirculatingSupply
            );
        }

        // @custom:note @todo actual white paper implementation is a distribution of additional carbon in protocol to G holders
        if (retirementKvcmQuote >= params.kvcmCirculatingSupply) revert Errors.CannotRetireEntireKvcmSupply();
    }

    // ***********
    // internal
    // **********

    /**
     * @dev Update the last update timestamp for price data
     * @param aam The address of the AAM
     * @param carbonClass The carbon class to update the last update timestamp for
     */
    function updateLastTimestamp(address aam, address carbonClass) external onlyOwner {
        IAssetManagerConfigFacet(aam).updateLastUpdateTimestamp(carbonClass);

        emit PriceDataUpdated(carbonClass, block.timestamp);
    }

    /**
     * @dev Resolve the class balance paths
     * @param params The parameters for the class balance paths
     * @return totalAmountForQuote The total amount for quote
     * @return discountedForwardTonnes The discounted forward tonnage
     * @return foundMaturity True if the maturity is found
     */
    function _resolveClassBalancePaths(ClassBalancePathsParams memory params)
        internal
        view
        returns (uint256 totalAmountForQuote, uint256 discountedForwardTonnes, bool foundMaturity)
    {
        if (
            params.discountedForwardBalanceForCurrentMidnightIndex == 0
                && params.discountForwardBalanceInitializedForDay
        ) {
            /* no prior adjusted forward balance for the day and already initialized, early return */
            return (params.amount, 0, true);
        }
        /* non-initialized paths */
        if (params.discountedForwardBalanceForCurrentMidnightIndex != 0) {
            /* adjusted class forward balance is set, use it */
            discountedForwardTonnes = params.discountedForwardBalanceForCurrentMidnightIndex;

            if (params.isLiquidSwap) {
                totalAmountForQuote = params.amount;
                foundMaturity = true;
            } else {
                uint256 discountFactor = _findDiscountFactor(params.discountFactors, params.targetMaturityId);
                /* revert for forward swap if no discount factor is found */
                if (discountFactor == 0 && params.targetMaturityId != 0) {
                    revert Errors.InvalidMaturityId(params.targetMaturityId);
                }
                totalAmountForQuote = OperationsMath.calculateDiscountedDelta(params.amount, discountFactor);
                foundMaturity = true;
            }
        } else if (params.discountedForwardBalanceForCurrentMidnightIndex == 0 && params.discountFactors.length > 0) {
            /* no adjusted class forward balance, but discount factors are set, use them */
            (totalAmountForQuote, discountedForwardTonnes, foundMaturity) = _getDiscountedForwardTonnage(
                params.isLiquidSwap,
                params.targetMaturityId,
                params.amount,
                params.discountFactors,
                params.maturitiesTonnes
            );

            if (params.isLiquidSwap) {
                totalAmountForQuote = params.amount;
            }
        } else {
            if (!params.isLiquidSwap) {
                // @dev if no discount factors for last seven days for forward swap --> revert
                revert Errors.NoDiscountFactorForMaturity(params.targetMaturityId);
            }
            totalAmountForQuote = params.amount;
            foundMaturity = true;
            if (params.isRetirement) {
                /*
                case: retirement with no adjusted forward balance and no discount factors.
                Including forwards undiscounted (totalTonnes fallback) inflates the denominator, shrinking
                the retirement quote so the retirer under-burns kVCM. Fall back to a
                liquid-supply-only denominator (exclude undiscounted forwards); the conservative direction
                for retirements (charge at least as much, never less).
                */
                discountedForwardTonnes = 0;
            } else {
                /*
                case: liquid swap with no adjusted class forward balance and no discount factors,
                --> use total tonnage as overpayment-limiting fallback
                @dev this mechanism only works because we revert for forward swaps if no current dfs are
                found, and we exclude forwards for retirements above. If either changes, revisit.
                */
                discountedForwardTonnes = params.totalTonnes - params.liquidSupplyForQuote;
            }
        }
    }

    /**
     * @dev Get the discounted forward tonnage
     * @param isLiquidSwap True if the swap is liquid, false otherwise
     * @param targetMaturityId The target maturity id
     * @param amount The amount of carbon credits to quote
     * @param discountFactors The discount factors
     * @param maturitiesTonnes The maturities tonnes
     */
    function _getDiscountedForwardTonnage(
        bool isLiquidSwap,
        uint256 targetMaturityId,
        uint256 amount,
        IRewardManager.MaturityDiscountFactor[] memory discountFactors,
        CommonStructs.MaturityTonnes[] memory maturitiesTonnes
    ) internal view returns (uint256 totalAmountForQuote, uint256 discountedForwardTonnage, bool foundMaturity) {
        uint256 maturityTonnesLen = maturitiesTonnes.length;

        if (maturityTonnesLen != discountFactors.length) {
            revert Errors.ActiveMaturityLengthMismatch(maturityTonnesLen, discountFactors.length);
        }

        for (uint256 i = 0; i < maturityTonnesLen;) {
            uint256 maturityId = maturitiesTonnes[i].maturityId;
            uint256 maturityTonnes = maturitiesTonnes[i].tonnes;
            uint256 discountFactor = discountFactors[i].discountFactor;

            // @dev pricing error guard where maturity tonnes != correct discount factor
            if (maturityId != discountFactors[i].maturityId) {
                revert Errors.MaturityIdMismatch(maturityId, discountFactors[i].maturityId);
            }

            if (!isLiquidSwap && maturityId == targetMaturityId) {
                totalAmountForQuote = OperationsMath.calculateDiscountedDelta(amount, discountFactor);
                foundMaturity = true;
            }

            discountedForwardTonnage += OperationsMath.calculateDiscountedForwardTonnage(maturityTonnes, discountFactor);

            unchecked {
                ++i;
            }
        }

        if (isLiquidSwap) {
            foundMaturity = true;
        }

        return (totalAmountForQuote, discountedForwardTonnage, foundMaturity);
    }

    /* ─────────────────────── EXTERNAL GETTERS ─────────────────────── */

    /**
     * @dev Get the last update timestamp for price data
     * @return The timestamp of the last price update
     */
    function getLastUpdateTimestamp(address aam, address carbonClass) external view returns (uint256) {
        ValidationLib.validateCarbonClass(aam, carbonClass);
        return IAssetManagerConfigFacet(aam).getLastUpdateTimestamp(carbonClass);
    }

    /**
     * @dev Check if the quoter supports a specific carbon class
     * @param carbonClass The carbon class to check
     * @return True if the class is supported, false otherwise
     */
    function supportsClass(address aam, address carbonClass) public view returns (bool) {
        return carbonClass == QuoterRouterFacet(aam).getClassForQuoter(address(this));
    }

    /* ─────────────────────── PURE HELPERS ─────────────────────── */

    function _findDiscountFactor(IRewardManager.MaturityDiscountFactor[] memory dfs, uint256 target)
        internal
        pure
        returns (uint256 df)
    {
        for (uint256 i = 0; i < dfs.length;) {
            if (dfs[i].maturityId == target) {
                return dfs[i].discountFactor; // early exit
            }
            unchecked {
                ++i;
            }
        }
        return df;
    }

    function unpackClassValuesForQuote(IQuoterRouterFacet.ClassValuesForQuote memory classValuesForQuote)
        internal
        pure
        returns (
            uint256 normalizedKvcmClassAllocation,
            uint256 normalizedK2ClassAllocation,
            uint256 totalTonnes,
            uint256 liquidSupplyForQuote,
            CommonStructs.MaturityTonnes[] memory maturitiesTonnes
        )
    {
        return (
            classValuesForQuote.normalizedKvcmClassAllocation,
            classValuesForQuote.normalizedK2ClassAllocation,
            classValuesForQuote.totalTonnes,
            classValuesForQuote.liquidSupplyForQuote,
            classValuesForQuote.maturitiesTonnes
        );
    }

    function unpackClassBalanceContext(IQuoterRouterFacet.ClassBalanceContext memory classBalanceContext)
        internal
        pure
        returns (
            uint256 currentMidnightIndex,
            bool discountForwardBalanceInitializedForDay,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            IRewardManager.MaturityDiscountFactor[] memory discountFactors,
            uint256[] memory activeMaturities
        )
    {
        return (
            classBalanceContext.currentMidnightIndex,
            classBalanceContext.discountForwardBalanceInitializedForDay,
            classBalanceContext.discountedForwardBalanceForCurrentMidnightIndex,
            classBalanceContext.discountFactors,
            classBalanceContext.activeMaturities
        );
    }
}
