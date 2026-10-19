// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICarbonClassVault} from "src/interfaces/ICarbonClassVault.sol";

interface IOperationsFacet {
    struct SwapCarbonCreditForKvcmParams {
        address carbonClass;
        address credit;
        uint256 tokenId;
        uint256 maturityId;
        uint256 amount;
        uint256 minKvcmOut;
        address recipient;
        ICarbonClassVault.CouponBurnParams couponBurnParams;
    }

    struct RetireCarbonCreditViaAggregatorParams {
        address carbonClass;
        address credit;
        uint256 tokenId;
        uint256 amount;
        uint256 maxKvcmIn;
        address payer;
        ICarbonClassVault.CouponBurnParams couponBurnParams;
    }

    event CarbonSwap(
        address indexed carbonClass,
        address indexed credit,
        address indexed quoter,
        uint256 tokenId,
        uint256 tonnageAmount,
        uint256 kvcmAmount,
        address recipient
    );

    event CarbonRetiredViaRA(
        address indexed carbonClass,
        address indexed credit,
        address indexed quoter,
        uint256 tokenId,
        uint256 tonnageAmount,
        address retiringEntity,
        string retiringReason
    );

    /**
     * @dev Swap carbon credits for KVCM tokens
     * @param swapParams The swap params
     * @return kvcmAmount The amount of KVCM tokens received
     */
    function swapCarbonCreditForKvcm(SwapCarbonCreditForKvcmParams memory swapParams)
        external
        returns (uint256 kvcmAmount);

    /**
     * @dev Retire carbon credits via the retirement aggregator
     * @param retireParams The retire params
     */
    function retireCarbonCreditViaAggregator(RetireCarbonCreditViaAggregatorParams memory retireParams) external;
}
