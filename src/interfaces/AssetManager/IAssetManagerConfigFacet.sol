// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

//interfaces
import {ICommonEvents} from "src/interfaces/ICommonEvents.sol";
import {AssetManagerStorage} from "src/libraries/storage/AssetManagerStorage.sol";

interface IAssetManagerConfigFacet is ICommonEvents {
    event AssetManagerConfigurationUpdated(AssetManagerStorage.AssetManagerConfig newConfig);

    function setConfiguration(AssetManagerStorage.AssetManagerConfig memory config) external;
    function getConfiguration() external view returns (AssetManagerStorage.AssetManagerConfig memory);

    function setRewardManager(address rewardManager) external;
    function getRewardManager() external view returns (address);

    function setStakingManager(address stakingManager) external;
    function getStakingManager() external view returns (address);

    function setMaturityManager(address maturityManager) external;
    function getMaturityManager() external view returns (address);

    function setKvcmToken(address _kvcm) external;
    function getKvcmToken() external view returns (address);

    // lastUpdateTimestamp
    function getLastUpdateTimestamp(address carbonClass) external view returns (uint256);
    function updateLastUpdateTimestamp(address carbonClass) external;
}
