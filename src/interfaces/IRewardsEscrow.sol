// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IRewardsEscrow
 * @dev Interface for the RewardsEscrow contract
 */
interface IRewardsEscrow {
    /**
     * @notice Transfer K2 tokens to the RewardManager
     * @param amount The amount of K2 to transfer
     */
    function transferK2ToRewardManager(uint256 amount) external;
}
