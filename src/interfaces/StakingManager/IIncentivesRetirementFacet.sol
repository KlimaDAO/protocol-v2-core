// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice KVCM lock retirement flows on the StakingManager diamond (`msg.sender` remains the lock owner).
interface IIncentivesRetirementFacet {
    /// @notice KVCM incentives debited for retirement before lock maturity.
    event IncentivesRetiredFromActiveLock(
        address indexed lockOwner,
        uint256 indexed lockId,
        uint128 maturityId,
        address incentiveToken,
        uint256 amount,
        address to
    );

    /// @notice Emitted when a matured lock is unlocked and KVCM is retired via the configured RA.
    event IncentivesRetiredOnUnlock(
        address indexed lockOwner,
        uint256 indexed lockId,
        uint128 maturityId,
        address incentiveToken,
        uint256 incentivesOut,
        uint256 actualRetired,
        uint256 returnedIncentives
    );

    /// @notice Emitted when remaining incentives from a partially-claimed lock are retired via the RA.
    event RemainingIncentivesRetired(
        address indexed lockOwner,
        uint256 indexed lockId,
        uint128 maturityId,
        address incentiveToken,
        uint256 incentivesOut,
        uint256 actualRetired,
        uint256 returned
    );

    struct RetireParams {
        address creditToken;
        uint256 tokenId;
        uint256 batchId;
        address carbonClass;
        uint256 maxKvcmIn;
        address beneficiaryAddress;
        string beneficiaryLocation;
        string beneficiaryString;
        string retirementMessage;
        string consumptionCountryCode;
        uint256 consumptionPeriodStart;
        uint256 consumptionPeriodEnd;
    }

    /// @notice Pre-maturity incentives → RA in one tx; lock stays open. Exactly `maxKvcmIn` incentives are claimed
    ///         and the full amount must be consumed by the RA (no partial retirement allowed).
    function retireKvcmIncentivesActiveLock(uint256 lockId, RetireParams calldata p) external;

    /// @notice Matured unlock payout → RA in one tx; `maxKvcmIn` caps RA spend; net inflow returned to `msg.sender`.
    function unlockAndRetire(uint256 lockId, RetireParams calldata p) external;

    /// @notice Claim remaining incentives from a PARTIAL_CLAIMED lock and retire up to `maxKvcmIn`; unused incentives returned to `msg.sender`.
    function retireRemainingIncentives(uint256 lockId, RetireParams calldata p) external;
}
