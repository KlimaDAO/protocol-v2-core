// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Errors} from "src/libraries/Errors.sol";
import {IQuoterManager} from "src/interfaces/AssetManager/IQuoterManager.sol";
import {ICarbonLedger} from "src/interfaces/ICarbonLedger.sol";
import {ICarbonClassVault} from "src/interfaces/ICarbonClassVault.sol";
import {AAMConstants} from "src/libraries/aam/AAMConstants.sol";

library ValidationLib {
    function validateCarbonClass(address aam, address carbonClass) internal view {
        address registeredQuoter = IQuoterManager(aam).getQuoterForClass(carbonClass);

        if (registeredQuoter != address(this)) {
            revert Errors.CarbonClassMismatch(carbonClass, registeredQuoter);
        }
    }

    function validateAmount(uint256 tonnes) internal pure {
        if (tonnes < AAMConstants.MIN_TONNAGE_AMOUNT) {
            revert Errors.InvalidAmountTooSmall(tonnes);
        }
        if (tonnes > AAMConstants.MAX_TONNAGE_AMOUNT) {
            revert Errors.InvalidAmountTooLarge(tonnes);
        }
    }

    function validateRegistration(
        ICarbonLedger carbonLedger,
        ICarbonClassVault carbonClassVault,
        address credit,
        uint256 tokenId
    ) internal view {
        if (!carbonLedger.isClassRegistered(address(carbonClassVault), true)) {
            revert Errors.ClassNotRegistered(address(carbonClassVault));
        }
        if (!carbonClassVault.isCarbonCreditRegistered(credit, tokenId)) {
            revert Errors.CarbonCreditNotRegisteredForClass(address(carbonClassVault), credit);
        }
    }

    function validateCoupon(uint256 couponAmount, uint256 couponBalance) internal pure {
        if (couponAmount > couponBalance) {
            revert Errors.InsufficientCouponRedemptionBalance(couponBalance, couponAmount);
        }
    }

    function validateCouponOwnership(uint256 couponAmount, address couponFrom, address validationAccount)
        internal
        view
    {
        if (couponAmount != 0 && couponFrom != validationAccount) {
            revert Errors.InvalidCouponBurnFrom(couponFrom, validationAccount);
        }
    }
}
