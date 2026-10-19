// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "../../libraries/storage/RewardManagerStorage.sol";
import {IRollUpdateFacet} from "./IRollUpdateFacet.sol";

interface IRewardManager {
    struct MaturityDiscountFactor {
        uint256 maturityId;
        uint64 discountFactor;
    }

    event LPRYRewardsTransferred(
        address indexed lpToken, uint256 indexed maturityId, address indexed user, uint256 amount
    );

    function getKvcmCirculatingSupply() external view returns (uint256);

    function getK2CirculatingSupply() external view returns (uint256);

    function mintForDeposit(address kvcm, address recipient, uint256 amount, uint256 tokenId) external;

    function getDiscountFactors(uint256 midnightIndex)
        external
        view
        returns (IRewardManager.MaturityDiscountFactor[] memory discountFactors, uint256[] memory activeMaturities);

    function calculateK2Reward(uint256 amount, uint256 timestamp) external view returns (uint256);

    function payK2Reward(address recipient, uint256 claimAmount, uint256 timestamp, address k2Token)
        external
        returns (uint256 paidReward);

    function getKvcmK2LpStakersRYDetails(uint256 maturityId) external view returns (uint256, uint256);
    function getKvcmQLpStakersRYDetails(uint256 maturityId) external view returns (uint256, uint256);

    function settleRYRewards(address lpToken, uint256 maturityId, address user, uint256 amount) external;
    function mintShareToLP(address lpToken, uint256 maturityId, address user, uint256 amount) external;
    function burnSharesFromLP(address lpToken, uint256 maturityId, address user) external;
    function claimLPRewards(address lpToken, uint256 maturityId) external;
    function getUserLPRYPosition(address lpToken, uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.LPRewardsPositionView memory position);
    function getLpStakersRYDetails(address lpToken, uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.GlobalRewardsState memory);

    function getK2StakersRYPosition(address user)
        external
        view
        returns (RewardManagerStorage.K2StakerPositionView memory position);
    function mintSharesForK2Staker(address user, uint256 amount) external;
    function burnSharesForK2Staker(address user, uint256 amount) external;
    function claimK2StakersRewards(address user) external;

    function mintSharesForKVCMStaker(uint256 maturityId, address user, uint256 amount) external;
    function burnSharesForKVCMStaker(uint256 maturityId, address user) external;
    function claimKVCMK2Rewards(uint256 maturityId) external;
    function getKVCMK2YieldPosition(uint256 maturityId, address user)
        external
        view
        returns (RewardManagerStorage.LPRewardsPositionView memory);
    function getKVCMK2YieldGlobalState(uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.GlobalRewardsState memory);

    function updateBetaSqForK2Allocation(uint256 k2Allocation_, address carbonClass_, uint256 dayId_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForK2Deallocation(uint256 k2Allocation_, address carbonClass_, uint256 dayId_)
        external
        returns (uint256 betaSq);

    function updateBetaSqForKvcmAllocation(uint256 k2Allocation_, address carbonClass_, uint256 dayId_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForKvcmDeallocation(uint256 k2Allocation_, address carbonClass_, uint256 dayId_)
        external
        returns (uint256 betaSq);

    function updateBetaSqForKvcmSupplyIncrease(uint256 kvcmSupplyChange_, uint256 dayId_)
        external
        returns (uint256 betaSq);
    function updateBetaSqForKvcmSupplyDecrease(uint256 kvcmSupplyChange_, uint256 dayId_)
        external
        returns (uint256 betaSq);

    function updateRewardsProportions(uint256 dayId_, uint256 totalK2Allocation_) external;

    function computeDayAheadLockYieldsAtIndex(uint128 midnightIndex)
        external
        view
        returns (
            IRollUpdateFacet.MaturityYields[] memory yields,
            uint256 currentCirculatingSupply,
            uint256 discountParameter
        );

    function distributeKvcmLockYieldForInterval(
        uint256 midnightIndex,
        uint256 discountParameter,
        uint256 circulatingSupplySnapshot,
        IRollUpdateFacet.MaturityYields[] memory maturityYields
    ) external;
}
