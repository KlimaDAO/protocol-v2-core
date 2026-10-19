// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";

interface IRMLPRewardsFacet {
    event LPRYieldTransferred(
        address indexed lpToken, uint256 indexed maturityId, address indexed user, uint256 amount
    );
    event LPK2YieldTransferred(
        address indexed lpToken, uint256 indexed maturityId, address indexed user, uint256 amount
    );
    event LPRYieldSharesMinted(
        address indexed lpToken,
        uint256 indexed maturityId,
        address indexed user,
        uint256 midnightIndex,
        uint256 pendingYield,
        uint256 sharesMinted
    );
    event LPRYieldSharesBurned(
        address indexed lpToken,
        uint256 indexed maturityId,
        address indexed user,
        uint256 midnightIndex,
        uint256 pendingYield,
        uint256 sharesBurned
    );
    event LPK2YieldSharesMinted(
        address indexed lpToken,
        uint256 indexed maturityId,
        address indexed user,
        uint256 midnightIndex,
        uint256 pendingYield,
        uint256 sharesMinted
    );
    event LPK2YieldSharesBurned(
        address indexed lpToken,
        uint256 indexed maturityId,
        address indexed user,
        uint256 midnightIndex,
        uint256 pendingYield,
        uint256 sharesBurned
    );

    function getUserLPRYEntries(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.Entry[] memory entries);
    function getUserLPK2YEntries(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.Entry[] memory entries);
    function previewClaimLPRewards(address lpToken, uint256 maturityId, address user)
        external
        returns (uint256 ryAmount, uint256 k2Amount);
}
