// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../libraries/LibDiamond.sol";
import "../../libraries/storage/RewardManagerStorage.sol";
import "../../libraries/CarbonSystemRoleLib.sol";
import "../../libraries/Errors.sol";
import {IRewardManagerConfigFacet} from "../../interfaces/RewardManager/IRewardManagerConfigFacet.sol";

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import "../../libraries/storage/RewardManagerStorage.sol";
import "../../libraries/Constants.sol";

/**
 * @title RewardManagerConfigFacet
 * @dev Facet for managing global system configuration
 */
contract RewardManagerConfigFacet is IRewardManagerConfigFacet {
    // Errors
    error NotAuthorized();

    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyOwnerOrSystemAdmin() {
        (bool hasRole,) = IAccessManager(RewardManagerStorage.rmConfig().accessManager)
            .hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (msg.sender != LibDiamond.contractOwner() && !hasRole) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    modifier nonZero(address value) {
        if (value == address(0)) revert Errors.ZeroAddress();
        _;
    }

    /// One-time initializer; owner-only
    function initAccessManager(address _accessManager) external nonZero(_accessManager) {
        if (RewardManagerStorage.configLayout().accessManager != address(0)) {
            revert Errors.AlreadyInitialized();
        }
        if (msg.sender != LibDiamond.contractOwner()) {
            revert Errors.NotAuthorized();
        }

        RewardManagerStorage.rmConfig().accessManager = _accessManager;
        emit AccessManagerUpdated(_accessManager);
    }

    function setRMConfiguration(RewardManagerStorage.RMConfig memory config) external onlyOwnerOrSystemAdmin {
        // verify each address is not zero address
        if (config.aam == address(0)) revert Errors.ZeroAddress();
        if (config.accessManager == address(0)) revert Errors.ZeroAddress();
        if (config.protocolSupplyOracle == address(0)) revert Errors.ZeroAddress();
        if (config.protocolMinter == address(0)) revert Errors.ZeroAddress();
        if (config.stakingManager == address(0)) revert Errors.ZeroAddress();
        if (config.kvcmToken == address(0)) revert Errors.ZeroAddress();
        if (config.k2Token == address(0)) revert Errors.ZeroAddress();
        if (config.maturityManager == address(0)) revert Errors.ZeroAddress();
        if (config.kvcmK2LPToken == address(0)) revert Errors.ZeroAddress();
        if (config.kvcmQLPToken == address(0)) revert Errors.ZeroAddress();
        if (config.riskyYieldToken == address(0)) revert Errors.ZeroAddress();
        if (config.k2YieldToken == address(0)) revert Errors.ZeroAddress();
        if (config.protocolRewardsEscrow == address(0)) revert Errors.ZeroAddress();

        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();
        rmConfig.aam = config.aam;
        rmConfig.accessManager = config.accessManager;
        rmConfig.protocolSupplyOracle = config.protocolSupplyOracle;
        rmConfig.protocolMinter = config.protocolMinter;
        rmConfig.stakingManager = config.stakingManager;
        rmConfig.kvcmToken = config.kvcmToken;
        rmConfig.k2Token = config.k2Token;
        rmConfig.maturityManager = config.maturityManager;
        rmConfig.kvcmK2LPToken = config.kvcmK2LPToken;
        rmConfig.kvcmQLPToken = config.kvcmQLPToken;
        rmConfig.riskyYieldToken = config.riskyYieldToken;
        rmConfig.k2YieldToken = config.k2YieldToken;
        rmConfig.protocolRewardsEscrow = config.protocolRewardsEscrow;

        RewardManagerStorage.kvcmLockYieldLayout().yieldDistributionInterval = Constants.YIELD_DISTRIBUTION_INTERVAL;
        emit RewardManagerConfigurationUpdated(config);
    }

    function getRMConfiguration() external view returns (RewardManagerStorage.RMConfig memory) {
        RewardManagerStorage.RMConfigLayout storage rmConfig = RewardManagerStorage.rmConfig();
        return RewardManagerStorage.RMConfig({
            aam: rmConfig.aam,
            accessManager: rmConfig.accessManager,
            protocolSupplyOracle: rmConfig.protocolSupplyOracle,
            protocolMinter: rmConfig.protocolMinter,
            stakingManager: rmConfig.stakingManager,
            kvcmToken: rmConfig.kvcmToken,
            k2Token: rmConfig.k2Token,
            maturityManager: rmConfig.maturityManager,
            kvcmK2LPToken: rmConfig.kvcmK2LPToken,
            kvcmQLPToken: rmConfig.kvcmQLPToken,
            riskyYieldToken: rmConfig.riskyYieldToken,
            k2YieldToken: rmConfig.k2YieldToken,
            protocolRewardsEscrow: rmConfig.protocolRewardsEscrow
        });
    }

    /* --- Individual Configuration --- */

    function setAccessManager(address _accessManager) external onlyOwnerOrSystemAdmin nonZero(_accessManager) {
        RewardManagerStorage.rmConfig().accessManager = _accessManager;
        emit AccessManagerUpdated(_accessManager);
    }

    function setSystemPaused(bool paused) external onlyOwner {
        RewardManagerStorage.managerPauseLayout().systemPaused = paused;
        emit SystemPauseStatusChanged(paused);
    }

    function setMaturityManager(address maturityManager) external onlyOwnerOrSystemAdmin nonZero(maturityManager) {
        RewardManagerStorage.configLayout().maturityManager = maturityManager;
        emit MaturityManagerUpdated(maturityManager);
    }

    function setAAM(address aam) external onlyOwnerOrSystemAdmin nonZero(aam) {
        RewardManagerStorage.configLayout().aam = aam;
        emit AAMUpdated(aam);
    }

    function setStakingManager(address stakingManager) external onlyOwnerOrSystemAdmin nonZero(stakingManager) {
        RewardManagerStorage.configLayout().stakingManager = stakingManager;
        emit StakingManagerUpdated(stakingManager);
    }

    function setKvcmToken(address kvcmToken) external onlyOwnerOrSystemAdmin nonZero(kvcmToken) {
        RewardManagerStorage.rmConfig().kvcmToken = kvcmToken;
        emit KvcmTokenUpdated(kvcmToken);
    }

    function setRiskyYieldToken(address riskyYieldToken) external onlyOwnerOrSystemAdmin nonZero(riskyYieldToken) {
        RewardManagerStorage.rmConfig().riskyYieldToken = riskyYieldToken;
        emit RiskyYieldTokenUpdated(riskyYieldToken);
    }

    function setK2YieldToken(address k2YieldToken) external onlyOwnerOrSystemAdmin nonZero(k2YieldToken) {
        RewardManagerStorage.rmConfig().k2YieldToken = k2YieldToken;
        emit K2YieldTokenUpdated(k2YieldToken);
    }

    function setKvcmK2LPToken(address kvcmK2LPToken) external onlyOwnerOrSystemAdmin nonZero(kvcmK2LPToken) {
        RewardManagerStorage.rmConfig().kvcmK2LPToken = kvcmK2LPToken;
        emit KvcmK2LPTokenUpdated(kvcmK2LPToken);
    }

    function setKvcmQLPToken(address kvcmQLPToken) external onlyOwnerOrSystemAdmin nonZero(kvcmQLPToken) {
        RewardManagerStorage.rmConfig().kvcmQLPToken = kvcmQLPToken;
        emit KvcmQLPTokenUpdated(kvcmQLPToken);
    }

    function setProtocolRewardsEscrow(address protocolRewardsEscrow)
        external
        onlyOwnerOrSystemAdmin
        nonZero(protocolRewardsEscrow)
    {
        RewardManagerStorage.rmConfig().protocolRewardsEscrow = protocolRewardsEscrow;
        emit ProtocolRewardsEscrowUpdated(protocolRewardsEscrow);
    }

    function setProtocolMinter(address protocolMinter) external onlyOwnerOrSystemAdmin nonZero(protocolMinter) {
        RewardManagerStorage.rmConfig().protocolMinter = protocolMinter;
        emit ProtocolMinterUpdated(protocolMinter);
    }

    function setYieldDistributionInterval(uint128 yieldDistributionInterval) external onlyOwnerOrSystemAdmin {
        RewardManagerStorage.kvcmLockYieldLayout().yieldDistributionInterval = yieldDistributionInterval;
        emit YieldDistributionIntervalUpdated(yieldDistributionInterval);
    }

    function setSupplyOracle(address supplyOracle) external onlyOwnerOrSystemAdmin nonZero(supplyOracle) {
        RewardManagerStorage.rmConfig().protocolSupplyOracle = supplyOracle;
        emit ProtocolSupplyOracleUpdated(supplyOracle);
    }

    /* --- Getter functions --- */

    function getAccessManager() external view returns (address) {
        return RewardManagerStorage.rmConfig().accessManager;
    }

    function getAAM() external view returns (address) {
        return RewardManagerStorage.rmConfig().aam;
    }

    function getStakingManager() external view returns (address) {
        return RewardManagerStorage.rmConfig().stakingManager;
    }

    function getMaturityManager() external view returns (address) {
        return RewardManagerStorage.rmConfig().maturityManager;
    }

    function getKvcmToken() external view returns (address) {
        return RewardManagerStorage.rmConfig().kvcmToken;
    }

    function getSupplyOracle() external view returns (address) {
        return RewardManagerStorage.rmConfig().protocolSupplyOracle;
    }

    function isSystemPaused() external view returns (bool) {
        return RewardManagerStorage.managerPauseLayout().systemPaused;
    }

    function getPauseStates() external view returns (RewardManagerStorage.RewardManagerPauseLayout memory) {
        return RewardManagerStorage.managerPauseLayout();
    }

    function getYieldDistributionInterval() external view returns (uint128) {
        return RewardManagerStorage.kvcmLockYieldLayout().yieldDistributionInterval;
    }

    function getRiskyYieldToken() external view returns (address) {
        return RewardManagerStorage.rmConfig().riskyYieldToken;
    }

    function getK2YieldToken() external view returns (address) {
        return RewardManagerStorage.rmConfig().k2YieldToken;
    }

    function getKvcmK2LPToken() external view returns (address) {
        return RewardManagerStorage.rmConfig().kvcmK2LPToken;
    }

    function getKvcmQLPToken() external view returns (address) {
        return RewardManagerStorage.rmConfig().kvcmQLPToken;
    }

    function getProtocolRewardsEscrow() external view returns (address) {
        return RewardManagerStorage.rmConfig().protocolRewardsEscrow;
    }

    function getProtocolMinter() external view returns (address) {
        return RewardManagerStorage.rmConfig().protocolMinter;
    }

    /// @notice Sets the last keeper update for reward pools (for testing/migration purposes)
    /// @param lpToken The LP token address (use address(0) for K2 stakers global)
    /// @param maturityId The maturity ID
    /// @param lastUpdate The midnight index (NOT timestamp) of the last keeper update
    function setLastKeeperUpdate(address lpToken, uint256 maturityId, uint256 lastUpdate) external onlyOwner {
        RewardManagerStorage.rmStorage().lpRYieldGlobal[lpToken][maturityId].lastKeeperUpdate = lastUpdate;
        RewardManagerStorage.rmStorage().lpK2YieldGlobal[lpToken][maturityId].lastKeeperUpdate = lastUpdate;
        RewardManagerStorage.rmStorage().k2StakersRYGlobal.lastKeeperUpdate = lastUpdate;
        RewardManagerStorage.rmStorage().k2StakersK2YieldGlobal.lastKeeperUpdate = lastUpdate;
    }

    function setProtocolSupplyOracle(address protocolSupplyOracle)
        external
        onlyOwnerOrSystemAdmin
        nonZero(protocolSupplyOracle)
    {
        RewardManagerStorage.rmConfig().protocolSupplyOracle = protocolSupplyOracle;
        emit ProtocolSupplyOracleUpdated(protocolSupplyOracle);
    }

    function getProtocolSupplyOracle() external view returns (address) {
        return RewardManagerStorage.rmConfig().protocolSupplyOracle;
    }
}
