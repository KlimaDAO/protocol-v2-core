// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";

interface IK2StakersRewardsFacet {
    event K2StakersRYRewardsTransferred(address indexed user, uint256 amount);
    event K2StakersK2RewardsTransferred(address indexed user, uint256 amount);
    event K2StakersRYSharesMinted(
        address indexed user, uint256 midnightIndex, uint256 pendingYield, uint256 sharesMinted
    );
    event K2StakersRYSharesBurned(
        address indexed user, uint256 midnightIndex, uint256 pendingYield, uint256 sharesBurned
    );
    event K2StakersK2YSharesMinted(
        address indexed user, uint256 midnightIndex, uint256 pendingYield, uint256 sharesMinted
    );
    event K2StakersK2YSharesBurned(
        address indexed user, uint256 midnightIndex, uint256 pendingYield, uint256 sharesBurned
    );

    function getK2StakersRYGlobalState() external view returns (RewardManagerStorage.GlobalRewardsState memory);
    function getK2StakersK2YieldGlobalState() external view returns (RewardManagerStorage.GlobalRewardsState memory);
    function getK2StakerRYEntries(address user) external view returns (RewardManagerStorage.Entry[] memory entries);
    function getK2StakerK2YEntries(address user) external view returns (RewardManagerStorage.Entry[] memory entries);
    function previewClaimK2StakersRewards(address user) external returns (uint256 ryAmount, uint256 k2Amount);
}
