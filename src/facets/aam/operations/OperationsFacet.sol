// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

//****** interfaces imports ******//
import {IOperationsFacet} from "src/interfaces/AssetManager/IOperationsFacet.sol";
import {IQuoterManager} from "src/interfaces/AssetManager/IQuoterManager.sol";
import {ICarbonLedger} from "src/interfaces/ICarbonLedger.sol";
import {IProtocolMinter} from "src/interfaces/IProtocolMinter.sol";
import {IQuoterRouterFacet} from "src/interfaces/AssetManager/IQuoterRouterFacet.sol";
import {IRiskyYieldFacet} from "src/interfaces/RewardManager/IRiskyYieldFacet.sol";

//****** openzeppelin imports ******//
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
//****** libraries imports ******//
import {AssetManagerStorage} from "src/libraries/storage/AssetManagerStorage.sol";
import {Errors} from "src/libraries/Errors.sol";
import {RateLimiterLib} from "src/libraries/aam/RateLimiterLib.sol";
import {ValidationLib} from "src/libraries/ValidationLib.sol";

contract OperationsFacet is IOperationsFacet, ReentrancyGuard {
    // @inheritdoc IOperationsFacet

    /* ─────────────────────── MODIFIERS ─────────────────────── */

    modifier whenNotPaused() {
        if (AssetManagerStorage.configLayout().systemPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }

    modifier onlyRA() {
        if (msg.sender != AssetManagerStorage.configLayout().aamConfig.retirementAggregator) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    /**
     * @dev Swap carbon credits for KVCM tokens by routing to the appropriate quoter
     * @param swapParams The swap params
     * - carbonClass: The carbon class of the token
     * - credit: The carbon credit token address
     * - tokenId: The token ID of the carbon credit
     * - maturityId: The maturity ID of the carbon credit
     * - amount: The amount of carbon credits to swap
     * - minKvcmOut: The minimum amount of KVCM tokens to receive
     * - recipient: The address to receive the KVCM tokens
     * - couponBurnParams: The coupon burn params
     * @return kvcmOut The amount of KVCM tokens received
     */
    function swapCarbonCreditForKvcm(SwapCarbonCreditForKvcmParams memory swapParams)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 kvcmOut)
    {
        if (swapParams.recipient == address(0)) revert Errors.InvalidRecipient();

        // Retrieve class quoter from the QuoterManagerFacet
        address quoter = IQuoterManager(address(this)).getQuoterForClass(swapParams.carbonClass);

        if (quoter == address(0)) revert Errors.NoQuoterForClass(swapParams.carbonClass);

        uint256 tonnes;
        bool isLiquidSwap;
        uint256 rawTokenAmount = swapParams.amount;
        IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext;

        ValidationLib.validateCouponOwnership(
            swapParams.couponBurnParams.tonnes, swapParams.couponBurnParams.from, msg.sender
        );

        // @dev an invalid credit will revert within the quote
        (tonnes, kvcmOut, isLiquidSwap, discountedForwardBalanceContext) = IQuoterRouterFacet(address(this))
            .getSwapQuote(
                swapParams.carbonClass,
                swapParams.credit,
                swapParams.tokenId,
                rawTokenAmount,
                swapParams.maturityId,
                swapParams.couponBurnParams
            );

        if (kvcmOut < swapParams.minKvcmOut) revert Errors.InsufficientKvcmOut(swapParams.minKvcmOut, kvcmOut);

        AssetManagerStorage.AssetManagerConfigLayout storage config = AssetManagerStorage.configLayout();

        // deposit credits to class vault
        ICarbonLedger(config.aamConfig.carbonLedger)
            .addCreditLiquidityToClassVault(
                swapParams.carbonClass,
                swapParams.credit,
                swapParams.tokenId,
                swapParams.maturityId,
                msg.sender,
                rawTokenAmount, // @dev do not convert to tonnes. deposit will convert.
                swapParams.couponBurnParams
            );

        _updateDiscountedForwardBalanceForCurrentMidnightIndex(
            isLiquidSwap, swapParams.carbonClass, discountedForwardBalanceContext
        );

        // Mint kVCM to AAM.
        // @dev will revert if kvcmOut is 0
        IProtocolMinter(config.aamConfig.protocolMinter).mintKvcmToAAM(kvcmOut);

        IRiskyYieldFacet(config.aamConfig.rewardManager)
            .updateBetaSqForKvcmSupplyIncrease(
                kvcmOut, swapParams.carbonClass, uint64(discountedForwardBalanceContext.currentMidnightIndex)
            );

        // Transfer kVCM to recipient
        SafeERC20.safeTransfer(IERC20(config.aamConfig.kvcm), swapParams.recipient, kvcmOut);

        emit CarbonSwap(
            swapParams.carbonClass, swapParams.credit, quoter, swapParams.tokenId, tonnes, kvcmOut, swapParams.recipient
        );

        return kvcmOut;
    }

    /**
     * @notice Retires carbon credits through the retirement aggregator
     * @param retireParams A RetireCarbonCreditViaAggregatorParams struct containing:
     *        - carbonClass: The carbon class to retire from
     *        - credit: The carbon credit token address
     *        - tokenId: The token ID of the carbon credit
     *        - amount: The amount of carbon credits to retire
     *        - maxKvcmIn: The maximum amount of KVCM to spend
     *        - couponBurnParams: The coupon burn params
     */
    function retireCarbonCreditViaAggregator(RetireCarbonCreditViaAggregatorParams memory retireParams)
        external
        onlyRA
        whenNotPaused
        nonReentrant
    {
        // Retrieve class quoter from the QuoterManagerFacet
        address quoter = IQuoterManager(address(this)).getQuoterForClass(retireParams.carbonClass);
        if (quoter == address(0)) revert Errors.NoQuoterForClass(retireParams.carbonClass);
        if (retireParams.payer == address(0)) revert Errors.ZeroAddress();

        uint256 rawTokenAmount = retireParams.amount;

        // @dev user transfers coupons to RA before calling retireCarbonCreditViaAggregator
        ValidationLib.validateCouponOwnership(
            retireParams.couponBurnParams.tonnes,
            retireParams.couponBurnParams.from,
            AssetManagerStorage.configLayout().aamConfig.retirementAggregator
        );

        // Retrieve quote
        (
            uint256 tonnes,
            uint256 quote,
            IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext,
            IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory updateLiquidSupplyRateLimiterParams
        ) = IQuoterRouterFacet(address(this))
            .getRetirementQuote(
                retireParams.carbonClass,
                retireParams.credit,
                retireParams.tokenId,
                rawTokenAmount,
                retireParams.couponBurnParams
            );

        AssetManagerStorage.AssetManagerConfigLayout storage config = AssetManagerStorage.configLayout();

        // in the retire path, this function will only set a value if a retirement is the first txn for the day
        _updateDiscountedForwardBalanceForCurrentMidnightIndex(
            true, retireParams.carbonClass, discountedForwardBalanceContext
        );

        _updateLiquidSupplyRateLimiter(retireParams.carbonClass, updateLiquidSupplyRateLimiterParams);

        if (retireParams.couponBurnParams.tonnes >= tonnes) {
            retireParams.couponBurnParams.tonnes = tonnes;
        }

        ICarbonLedger(config.aamConfig.carbonLedger)
            .removeCreditLiquidityFromClassVault(
                retireParams.carbonClass,
                retireParams.credit,
                retireParams.tokenId,
                0, // maturityId. pass 0 as default liquid maturity
                rawTokenAmount, // @dev do not convert to tonnes. removal will handle conversion based on credit.
                config.aamConfig.retirementAggregator,
                retireParams.couponBurnParams
            );

        // Receive Kvcm from the RA
        uint256 kvcmReceived = _receiveKvcm(quote, retireParams.payer);

        if (kvcmReceived > retireParams.maxKvcmIn) {
            revert Errors.MaxKvcmInExceeded(retireParams.maxKvcmIn, kvcmReceived);
        }

        // burn kvcm
        _burnKvcm(kvcmReceived);

        IRiskyYieldFacet(config.aamConfig.rewardManager)
            .updateBetaSqForKvcmSupplyDecrease(
                kvcmReceived, retireParams.carbonClass, uint64(discountedForwardBalanceContext.currentMidnightIndex)
            );

        emit CarbonRetiredViaRA(
            retireParams.carbonClass,
            retireParams.credit,
            quoter,
            retireParams.tokenId,
            tonnes,
            config.aamConfig.retirementAggregator,
            "Retired via Aggregator"
        );
    }

    /* ─────────────────────── INTERNAL HELPERS ─────────────────────── */

    function _updateLiquidSupplyRateLimiter(
        address carbonClass,
        IQuoterRouterFacet.UpdateLiquidSupplyRateLimiterParams memory params
    ) internal {
        RateLimiterLib.updateLiquidSupplyRateLimiter(carbonClass, params);
    }

    function _updateDiscountedForwardBalanceForCurrentMidnightIndex(
        bool isLiquidSwap,
        address carbonClass,
        IQuoterRouterFacet.DiscountedForwardBalanceContext memory discountedForwardBalanceContext
    ) internal {
        AssetManagerStorage.ClassQuoterLayout storage quoterLayout = AssetManagerStorage.classQuoterLayout();
        uint256 midnightIndex = discountedForwardBalanceContext.currentMidnightIndex;

        AssetManagerStorage.DiscountedForwardBalanceIndexRecord storage discountedForwardBalanceIndexRecord =
            quoterLayout.discountedForwardBalancesForCurrentMidnightIndex[midnightIndex][carbonClass];

        // always initialize on first update
        if (!discountedForwardBalanceIndexRecord.discountForwardBalanceInitializedForDay) {
            discountedForwardBalanceIndexRecord.discountForwardBalanceInitializedForDay = true;
            discountedForwardBalanceIndexRecord.discountedForwardBalanceForCurrentMidnightIndex =
            discountedForwardBalanceContext.discountedForwardBalanceForCurrentMidnightIndex;
        }

        /* Only forward swaps move the balance within a day (liquid swaps do not). If a forward, this amount is the discounted amount used for the quote */
        uint256 amountUsedForSwapQuote = discountedForwardBalanceContext.amountUsedForSwapQuote;

        if (!isLiquidSwap && amountUsedForSwapQuote != 0) {
            uint256 newBalance = discountedForwardBalanceIndexRecord.discountedForwardBalanceForCurrentMidnightIndex
                + amountUsedForSwapQuote;

            if (newBalance > discountedForwardBalanceIndexRecord.discountedForwardBalanceForCurrentMidnightIndex) {
                discountedForwardBalanceIndexRecord.discountedForwardBalanceForCurrentMidnightIndex = newBalance;
            }
        }
    }

    /* ─────────────────────── kVCM Utils ─────────────────────── */

    function _receiveKvcm(uint256 amount, address sender) internal returns (uint256 receivedAmount) {
        if (amount == 0) return 0;
        address kvcm = AssetManagerStorage.configLayout().aamConfig.kvcm;
        SafeERC20.safeTransferFrom(IERC20(kvcm), sender, address(this), amount);
        return amount;
    }

    function _burnKvcm(uint256 amount) internal {
        ERC20Burnable(AssetManagerStorage.configLayout().aamConfig.kvcm).burn(amount);
    }
}
