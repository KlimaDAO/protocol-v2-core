// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICarbonClassVault} from "src/interfaces/ICarbonClassVault.sol";
import {ICarbonClassQuoter} from "src/interfaces/AssetManager/ICarbonClassQuoter.sol";
import {IRewardManager} from "../RewardManager/IRewardManager.sol";
import {CommonStructs} from "src/libraries/CommonStructs.sol";
/**
 * @title IQuoterRouterFacet
 * @dev Interface for the QuoterRouterFacet which routes quote requests to appropriate quoters
 */

interface IQuoterRouterFacet {
    // Errors
    error NotAuthorized();
    error InvalidCarbonClass(address carbonClass);
    error NoQuoterForClass(address carbonClass);
    error InvalidRecipient();
    error SwapFailed(address quoter, bytes reason);
    error RetirementFailed(address quoter, bytes reason);
    error InsufficientKvcmOut(uint256 expected, uint256 actual);

    /**
     * @dev Parameters for class balance context
     * @param currentMidnightIndex The current midnight index
     * @param discountForwardBalanceInitializedForDay Whether the discount forward balance is initialized for the day
     * @param discountedForwardBalanceForCurrentMidnightIndex The discounted forward balance for the current midnight index
     * @param discountFactors The discount factors
     * @param activeMaturities The active maturities
     */
    struct ClassBalanceContext {
        uint256 currentMidnightIndex;
        bool discountForwardBalanceInitializedForDay;
        uint256 discountedForwardBalanceForCurrentMidnightIndex;
        IRewardManager.MaturityDiscountFactor[] discountFactors;
        uint256[] activeMaturities;
    }
    /**
     * @dev Parameters for class values for quote
     * @param normalizedKvcmClassAllocation The normalized kvcm class allocation
     * @param normalizedK2ClassAllocation The normalized kvcm x class allocation
     * @param totalTonnes The total tonnage
     * @param liquidSupplyForQuote The liquid supply for the quote
     * @param maturitiesTonnes The maturities tonnes
     */

    struct ClassValuesForQuote {
        uint256 normalizedKvcmClassAllocation;
        uint256 normalizedK2ClassAllocation;
        uint256 totalTonnes;
        uint256 liquidSupplyForQuote;
        CommonStructs.MaturityTonnes[] maturitiesTonnes;
    }
    /**
     * @dev Parameters for discounted forward balance context
     * @param currentMidnightIndex The current midnight index
     * @param amountUsedForSwapQuote The discounted delta for the swap
     * @param discountedForwardBalanceForCurrentMidnightIndex The discounted forward balance for the current midnight index
     */

    struct DiscountedForwardBalanceContext {
        uint256 currentMidnightIndex;
        uint256 amountUsedForSwapQuote;
        uint256 discountedForwardBalanceForCurrentMidnightIndex;
    }

    /**
     * @dev Parameters for updating the liquid supply rate limiter
     * @param preTxnLiquidSupply The liquid supply before the transaction
     */
    struct UpdateLiquidSupplyRateLimiterParams {
        uint256 preTxnLiquidSupply;
    }

    /**
     * @dev Get a quote for swapping carbon credits to KVCM
     * @param carbonClass The carbon class to quote
     * @param credit The carbon credit token address
     * @param tokenId The token ID of the carbon credit
     * @param amount The amount of carbon credits to quote
     * @param maturityId The maturity ID of the carbon credit
     * @param couponBurnParams Parameters for burning coupons during the swap
     * @return tonnes The amount of carbon credits in tonnes
     * @return price The price quote for the specified amount
     * @return isLiquidSwap Whether this is a liquid swap
     * @return discountedForwardBalanceContext The discounted forward balance context
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
        returns (
            uint256 tonnes,
            uint256 price,
            bool isLiquidSwap,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext
        );

    /**
     * @dev Get a quote for retiring a specific carbon credit
     * @param carbonClass The carbon class of the token
     * @param credit The carbon credit token address
     * @param tokenId The token ID
     * @param amount The amount of carbon credits to quote
     * @param couponBurnParams Parameters for burning coupons during retirement
     * @return tonnes The amount of carbon credits in tonnes
     * @return kvcmRetirementPrice The price quote for the specified amount
     * @return discountedForwardBalanceContext The discounted forward balance context
     * @return updateLiquidSupplyRateLimiterParams The update liquid supply rate limiter parameters
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
        returns (
            uint256 tonnes,
            uint256 kvcmRetirementPrice,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext,
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory updateLiquidSupplyRateLimiterParams
        );

    /**
     * @dev Inverse retirement quote: given a kVCM budget, return the tonnes retired of a specific class
     * @param carbonClass The carbon class of the token
     * @param credit The carbon credit token address
     * @param tokenId The token ID
     * @param kvcmIn The kVCM budget to spend on retirement
     * @param couponBurnParams Parameters for burning coupons during retirement
     * @return tonnes The total tonnes the budget (plus coupon) retires
     * @return tokenAmount The credit's native token amount to pass to the retire entrypoint (coupon tonnes excluded)
     * @return kvcmRetirementPrice The kVCM price of retiring `tokenAmount`, exactly as the retire entrypoint charges it. It never exceeds kvcmIn
     * @return discountedForwardBalanceContext The discounted forward balance context
     * @return updateLiquidSupplyRateLimiterParams The update liquid supply rate limiter parameters
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
        returns (
            uint256 tonnes,
            uint256 tokenAmount,
            uint256 kvcmRetirementPrice,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext,
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory updateLiquidSupplyRateLimiterParams
        );

    /**
     * @dev Get the carbon class associated with a quoter
     * @param quoter The quoter address
     * @return The carbon class address
     */
    function getClassForQuoter(address quoter) external view returns (address);

    /**
     * @dev Get the discounted forward balance for the current midnight index
     * @param midnightIndex The midnight index
     * @param carbonClass The carbon class
     * @return initialized Whether the discounted forward balance is initialized for the day
     * @return storedBaseline The stored baseline for the discounted forward balance
     */
    function getDiscountedForwardBalanceRecordForIndex(uint256 midnightIndex, address carbonClass)
        external
        view
        returns (bool initialized, uint256 storedBaseline);
}
