// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IProtocolRewardsEscrow {
    event ConfigurationUpdated(EscrowConfig prevConfig, EscrowConfig newConfig);
    event K2RewardsEscrowed(uint256 amount);
    event K2RewardsTransferredToTreasury(uint256 amount);
    event K2RewardsTransferredToRewardManager(uint256 amount);
    event EscrowLimitsUpdated(EscrowLimits newLimits);

    struct EscrowConfig {
        address k2Token;
        address kvcmToken;
        address treasury;
        address rewardManager;
        address accessManager;
    }

    struct EscrowLimits {
        uint256 maxK2EscrowAmount;
    }

    struct EscrowBalance {
        uint256 k2RewardsEscrowed;
    }

    function escrowK2Rewards(uint256 amount) external;
    function transferK2ToTreasury(uint256 totalK2YieldForTreasury) external;
    function transferK2ToRewardManager(uint256 totalK2YieldForRewardManager) external;
    function setEscrowLimits(EscrowLimits memory limits) external;
    function getEscrowBalance() external view returns (EscrowBalance memory);
    function getEscrowConfig() external view returns (EscrowConfig memory);
    function getEscrowLimits() external view returns (EscrowLimits memory);
    function setConfiguration(EscrowConfig memory config) external;
}
