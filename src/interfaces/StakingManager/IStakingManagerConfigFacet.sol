// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICommonEvents} from "src/interfaces/ICommonEvents.sol";
import {StakingManagerStorage} from "../../libraries/storage/StakingManagerStorage.sol";

interface IStakingManagerConfigFacet is ICommonEvents {
    // Events
    event StakingManagerConfigurationUpdated(
        StakingManagerStorage.StakingManagerConfig newConfig,
        StakingManagerStorage.IntegrationConfig newIntegrationConfig
    );
    event IntegrationConfigurationUpdated(StakingManagerStorage.IntegrationConfig newIntegrationConfig);
    event KvcmLockUpdated(address kvcmLock);
    event LockAmountsUpdated(uint256 minLockAmount, uint256 maxLockAmount);
    event K2LockPeriodUpdated(uint256 minLockPeriod);
    event ZkMeCooperatorUpdated(address zkMeCooperator);
    event ZkMeVerifyUpdated(address zkMeVerify);
    event ZkMeRequiredUpdated(bool zkMeRequired);

    /**
     * Access Manager **
     */
    function initAccessManager(address _accessManager) external;

    function setAccessManager(address accessManager) external;

    function getAccessManager() external view returns (address);

    function setAAM(address aam) external;

    function getAAM() external view returns (address);

    function setKvcmToken(address kvcmToken) external;

    function getKvcmToken() external view returns (address);

    function setK2Token(address k2Token) external;

    function getK2Token() external view returns (address);

    function setMaturityManager(address maturityManager) external;

    function getMaturityManager() external view returns (address);

    function setRewardManager(address rewardManager) external;

    function getRewardManager() external view returns (address);

    function setCarbonLedger(address carbonLedger) external;

    function getCarbonLedger() external view returns (address);

    function setZkMeCooperator(address zkMeCooperator) external;

    function getZkMeCooperator() external view returns (address);

    function setZkMeVerify(address zkMeVerify) external;

    function getZkMeVerify() external view returns (address);

    function setZkMeRequired(bool zkMeRequired) external;

    function getZkMeRequired() external view returns (bool);

    function setKvcmLock(address kvcmLock) external;

    function setRetirementAggregator(address retirementAggregator) external;

    function getRetirementAggregator() external view returns (address);

    /* --- K2 Staking --- */

    function setK2LockLimits(uint256 minLockAmount, uint256 maxLockAmount) external;

    function getK2LockLimits() external view returns (uint256 minLockAmount, uint256 maxLockAmount);

    function setK2LockPeriod(uint256 minLockPeriod) external;

    function getK2LockPeriod() external view returns (uint256);

    function setConfiguration(
        StakingManagerStorage.StakingManagerConfig memory config,
        StakingManagerStorage.IntegrationConfig memory integrationConfig
    ) external;

    function getStakingManagerConfiguration()
        external
        view
        returns (
            StakingManagerStorage.StakingManagerConfig memory config,
            StakingManagerStorage.IntegrationConfig memory integrationConfig
        );
}
