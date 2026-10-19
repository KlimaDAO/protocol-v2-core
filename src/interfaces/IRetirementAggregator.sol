// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRetirementAggregator {
    struct RetireDetails {
        address retiringAddress;
        string retiringEntityString;
        address beneficiaryAddress;
        string beneficiaryString;
        string retirementMessage;
        string beneficiaryLocation;
        string consumptionCountryCode;
        uint256 consumptionPeriodStart;
        uint256 consumptionPeriodEnd;
    }

    function retireCreditViaKlima(
        address creditToken,
        uint256 tokenId,
        uint256 batchId,
        uint256 amount,
        address inputTokenAddress,
        address carbonClass,
        uint256 maxInputTokenIn,
        uint256 couponTonnes,
        RetireDetails memory details
    ) external;
}
