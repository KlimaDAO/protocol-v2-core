// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";

interface IRMKVCMStakers {
    event KVCMK2YieldTransferred(uint256 indexed maturityId, address indexed user, uint256 amount);
    event KVCMK2YieldSharesMinted(
        uint256 indexed maturityId,
        address indexed user,
        uint256 midnightIndex,
        uint256 pendingYield,
        uint256 sharesMinted
    );
    event KVCMK2YieldSharesBurned(
        uint256 indexed maturityId,
        address indexed user,
        uint256 midnightIndex,
        uint256 pendingYield,
        uint256 sharesBurned
    );

    function mintSharesForKVCMStaker(uint256 maturityId, address user, uint256 amount) external;
    function burnSharesForKVCMStaker(uint256 maturityId, address user) external;
    function burnSharesForKVCMStaker(uint256 maturityId, address user, address to) external;
    function claimKVCMK2Rewards(uint256 maturityId) external;
    function getKVCMK2YEntries(uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.Entry[] memory entries);
    function previewClaimKVCMK2Rewards(uint256 maturityId, address user) external returns (uint256 k2Amount);
}
