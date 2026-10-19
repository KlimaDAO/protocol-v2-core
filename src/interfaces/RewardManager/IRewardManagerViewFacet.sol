// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RewardManagerStorage} from "src/libraries/storage/RewardManagerStorage.sol";
import {IRewardManager} from "src/interfaces/RewardManager/IRewardManager.sol";

interface IRewardManagerViewFacet {
    function getKvcmLock(uint256 lockId) external view returns (RewardManagerStorage.KvcmLockView memory);

    function getDiscountFactor(uint256 midnightIndex, uint256 maturityId) external view returns (uint64 discountFactor);

    function getDiscountFactors(uint256 midnightIndex)
        external
        view
        returns (IRewardManager.MaturityDiscountFactor[] memory discountFactors, uint256[] memory activeMaturities);
    function getLastMidnightIndexYieldDistribution() external view returns (uint256);
    function getIntervalSettled(uint256 midnightIndex) external view returns (bool);
    function getCurrentMaturityTotals(uint256 maturityId)
        external
        view
        returns (uint256 totalRawPrincipal, uint256 totalSharesForMaturity);

    // Debug views
    function getLPRYAccSnapshot(address lpToken, uint256 maturityId, uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory);

    function getLPK2YAccSnapshot(address lpToken, uint256 maturityId, uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory);

    function getK2RYAccSnapshot(uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory);

    function getK2K2YAccSnapshot(uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory);

    function getKVCMK2YAccSnapshot(uint256 maturityId, uint256 midnightIndex)
        external
        view
        returns (RewardManagerStorage.AccumulatorSnapshot memory);

    function getIntervalData(uint256 midnightIndex) external view returns (RewardManagerStorage.IntervalData memory);

    function getMaturityIntervalData(uint256 midnightIndex, uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.MaturityIntervalData memory);

    function getFullMaturityTotals(uint256 maturityId)
        external
        view
        returns (RewardManagerStorage.MaturityTotals memory);
}
