// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/interfaces/ICommonEvents.sol";
import {RewardManagerStorage} from "src/libraries/storage/RewardManagerStorage.sol";

interface IRewardManagerConfigFacet is ICommonEvents {
    // ============================================================================
    // Events
    // ============================================================================

    event RewardManagerConfigurationUpdated(RewardManagerStorage.RMConfig newConfig);
    event KvcmK2LPTokenUpdated(address kvcmK2LPToken);
    event KvcmQLPTokenUpdated(address kvcmQLPToken);
    event ProtocolRewardsEscrowUpdated(address indexed protocolRewardsEscrow);
    event ProtocolMinterUpdated(address indexed protocolMinter);

    // ============================================================================
    // Configuration Management
    // ============================================================================

    function setRMConfiguration(RewardManagerStorage.RMConfig memory config) external;
    function getRMConfiguration() external view returns (RewardManagerStorage.RMConfig memory);

    // ============================================================================
    // Access Manager
    // ============================================================================

    function initAccessManager(address _accessManager) external;
    function setAccessManager(address accessManager) external;
    function getAccessManager() external view returns (address);

    // ============================================================================
    // Core Protocol Addresses
    // ============================================================================

    function setAAM(address aam) external;
    function getAAM() external view returns (address);

    function setMaturityManager(address maturityManager) external;
    function getMaturityManager() external view returns (address);

    function setStakingManager(address stakingManager) external;
    function getStakingManager() external view returns (address);

    function setProtocolSupplyOracle(address protocolSupplyOracle) external;
    function getProtocolSupplyOracle() external view returns (address);

    // ============================================================================
    // Token Addresses
    // ============================================================================

    function setKvcmToken(address kvcmToken) external;
    function getKvcmToken() external view returns (address);

    function setRiskyYieldToken(address riskyYieldToken) external;
    function getRiskyYieldToken() external view returns (address);

    function setK2YieldToken(address k2YieldToken) external;
    function getK2YieldToken() external view returns (address);

    function setKvcmK2LPToken(address kvcmK2LPToken) external;
    function getKvcmK2LPToken() external view returns (address);

    function setKvcmQLPToken(address kvcmQLPToken) external;
    function getKvcmQLPToken() external view returns (address);

    function setProtocolMinter(address protocolMinter) external;
    function getProtocolMinter() external view returns (address);

    function setProtocolRewardsEscrow(address protocolRewardsEscrow) external;
    function getProtocolRewardsEscrow() external view returns (address);

    // ============================================================================
    // System Parameters
    // ============================================================================

    function setSystemPaused(bool paused) external;
    function isSystemPaused() external view returns (bool);
    function getPauseStates() external view returns (RewardManagerStorage.RewardManagerPauseLayout memory);

    function setYieldDistributionInterval(uint128 yieldDistributionInterval) external;
    function getYieldDistributionInterval() external view returns (uint128);

    function setLastKeeperUpdate(address lpToken, uint256 maturityId, uint256 lastUpdate) external;
}
