// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICarbonClassVault} from "src/interfaces/ICarbonClassVault.sol";
import {IRewardManager} from "../RewardManager/IRewardManager.sol";
import {CommonStructs} from "src/libraries/CommonStructs.sol";
import {IQuoterRouterFacet} from "src/interfaces/AssetManager/IQuoterRouterFacet.sol";
/**
 * @title ICarbonClassQuoter
 * @dev Interface for carbon class implementations
 * All specific carbon classes must implement this interface
 */

interface ICarbonClassQuoter {
    event PriceDataUpdated(address indexed carbonClass, uint256 timestamp);

    /**
     * @dev Parameters for maturity data
     * @param discountFactor The discount factor
     * @param maturityAmount The maturity amount
     * @param maturityId The maturity id
     */
    struct MaturityData {
        uint256 discountFactor;
        uint256 maturityAmount;
        uint256 maturityId;
    }

    /**
     * @dev Parameters for quoting a swap
     * @param isLiquidSwap Whether the swap is liquid
     * @param carbonLedger The carbon ledger address
     * @param maturityManager The maturity manager address
     * @param carbonClass The carbon class to quote for
     * @param credit The credit address
     * @param tokenId The token id
     * @param maturityId The maturity id
     * @param systemPaused Whether the system is paused
     * @param kvcmCirculatingSupply The kvcm circulating supply
     * @param classBalanceContext The class balance context
     * @param classValuesForQuote The class values for quote
     */
    struct QuoteSwapParams {
        bool isLiquidSwap;
        address carbonLedger;
        address maturityManager;
        address carbonClass;
        address credit;
        uint256 tokenId;
        uint256 maturityId;
        bool systemPaused;
        uint256 kvcmCirculatingSupply;
        IQuoterRouterFacet.ClassBalanceContext classBalanceContext;
        IQuoterRouterFacet.ClassValuesForQuote classValuesForSwapQuote;
    }
    /**
     * @dev Parameters for quoting a retirement
     * @param carbonLedger The carbon ledger address
     * @param stakingManager The staking manager address
     * @param rewardManager The rewards manager address
     * @param carbonClass The carbon class to quote for
     * @param credit The credit address
     * @param tokenId The token id
     * @param systemPaused Whether the system is paused
     * @param kvcmCirculatingSupply The kvcm circulating supply
     * @param classBalanceContext The class balance context
     * @param classValuesForRetireQuote The class values for retire quote
     */

    struct QuoteRetirementParams {
        address carbonLedger;
        address carbonClass;
        address credit;
        uint256 tokenId;
        bool systemPaused;
        uint256 kvcmCirculatingSupply;
        IQuoterRouterFacet.ClassBalanceContext classBalanceContext;
        IQuoterRouterFacet.ClassValuesForQuote classValuesForRetireQuote;
    }

    /**
     * @dev Parameters for resolving class balance paths
     * @param amount The amount of carbon credits to quote
     * @param targetMaturityId The target maturity id
     * @param isLiquidSwap True if the swap is liquid, false otherwise
     * @param isRetirement True txn is a retirement, false if swap
     * @param maturitiesTonnes The maturities tonnes
     * @param discountForwardBalanceInitializedForDay True if the discount forward balance is initialized for the day
     * @param discountedForwardBalanceForCurrentMidnightIndex The discounted forward balance for the current midnight index
     * @param discountFactors The discount factors
     * @param totalTonnes The total tonnage
     * @dev liquid supply: swaps == rate limited, retirements == raw
     * @param liquidSupplyForQuote The liquid supply for the quote
     */
    struct ClassBalancePathsParams {
        uint256 amount;
        uint256 targetMaturityId;
        bool isLiquidSwap;
        bool isRetirement;
        CommonStructs.MaturityTonnes[] maturitiesTonnes;
        bool discountForwardBalanceInitializedForDay;
        uint256 discountedForwardBalanceForCurrentMidnightIndex;
        IRewardManager.MaturityDiscountFactor[] discountFactors;
        uint256 totalTonnes;
        uint256 liquidSupplyForQuote;
    }

    /**
     * @dev Check if the quoter supports a specific carbon class
     * @param carbonClass The carbon class to check
     * @return True if the class is supported, false otherwise
     */
    function supportsClass(address aam, address carbonClass) external view returns (bool);

    /**
     * @dev Get the last update timestamp for price data
     * @return The timestamp of the last price update
     */
    function getLastUpdateTimestamp(address aam, address carbonClass) external view returns (uint256);

    /**
     * @dev Quote the price for swapping carbon credits to KVCM with a coupon
     * @param params The parameters for the swap quote
     * @param couponBurnParams The parameters for the coupon burn
     * @return tonnes The amount of carbon credits in tonnes
     * @return kvcmPrice The price quote for the specified swap
     * @return isLiquidSwap True if the swap is liquid, false otherwise
     * @return amountUsedForSwapQuote The amount of carbon credits in tonnes that are discounted for the swap
     * @return discountedForwardBalanceForCurrentMidnightIndex The discounted forward balance for the current midnight index
     */
    function quoteSwap(
        uint256 amount,
        QuoteSwapParams memory params,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        returns (
            uint256 tonnes,
            uint256 kvcmPrice,
            bool isLiquidSwap,
            uint256 amountUsedForSwapQuote,
            uint256 discountedForwardBalanceForCurrentMidnightIndex
        );

    /**
     * @dev Quote the price for retiring a specific carbon credit with a coupon
     * @param params The parameters for the retirement quote
     * @param couponBurnParams The parameters for the coupon burn
     * @return tonnes The amount of carbon credits in tonnes
     * @return kvcmRetirementPrice The price quote for the specified retirement
     * @return discountedForwardBalanceForCurrentMidnightIndex The discounted forward balance for the current midnight index
     * @return preTxnLiquidSupply The liquid supply before the transaction
     */
    function quoteRetirement(
        address aam,
        uint256 amount,
        QuoteRetirementParams memory params,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        returns (
            uint256 tonnes,
            uint256 kvcmRetirementPrice,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            uint256 preTxnLiquidSupply
        );

    /**
     * @dev Inverse retirement quote: given a kVCM budget, return the tonnes that budget retires.
     * @param kvcmIn The kVCM budget to spend on retirement
     * @param params The parameters for the retirement quote
     * @param couponBurnParams The parameters for the coupon burn (coupon tonnes are added on top of the budget-derived tonnes)
     * @return tonnes The total tonnes retired (budget-derived tonnes + coupon tonnes)
     * @return tokenAmount The credit's native token amount to pass to the retire entrypoint (coupon tonnes excluded)
     * @return kvcmRetirementPrice The kVCM price of retiring `tokenAmount`, exactly as the retire entrypoint charges it. It never exceeds kvcmIn
     * @return discountedForwardBalanceForCurrentMidnightIndex The discounted forward balance for the current midnight index
     * @return preTxnLiquidSupply The liquid supply before the transaction
     */
    function quoteRetirementForKvcmIn(
        address aam,
        uint256 kvcmIn,
        QuoteRetirementParams memory params,
        ICarbonClassVault.CouponBurnParams memory couponBurnParams
    )
        external
        view
        returns (
            uint256 tonnes,
            uint256 tokenAmount,
            uint256 kvcmRetirementPrice,
            uint256 discountedForwardBalanceForCurrentMidnightIndex,
            uint256 preTxnLiquidSupply
        );
}
