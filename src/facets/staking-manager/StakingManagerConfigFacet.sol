// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {StakingManagerStorage} from "../../libraries/storage/StakingManagerStorage.sol";
import {CarbonSystemRoleLib} from "../../libraries/CarbonSystemRoleLib.sol";
import {Errors} from "../../libraries/Errors.sol";
import {IStakingManagerConfigFacet} from "../../interfaces/StakingManager/IStakingManagerConfigFacet.sol";

import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title StakingManagerConfigFacet
 * @dev Facet for managing global system configuration
 */
contract StakingManagerConfigFacet is IStakingManagerConfigFacet {
    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyOwnerOrSystemAdmin() {
        (bool hasRole,) = IAccessManager(StakingManagerStorage.configLayout().accessManager)
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

    // Initializer functions
    /// One-time initializer; owner-only
    function initAccessManager(address _accessManager) external nonZero(_accessManager) {
        if (StakingManagerStorage.configLayout().accessManager != address(0)) {
            revert Errors.AlreadyInitialized();
        }
        if (msg.sender != LibDiamond.contractOwner()) {
            revert Errors.NotAuthorized();
        }

        StakingManagerStorage.configLayout().accessManager = _accessManager;
        emit AccessManagerUpdated(_accessManager);
    }

    function setConfiguration(
        StakingManagerStorage.StakingManagerConfig memory config,
        StakingManagerStorage.IntegrationConfig memory integrationConfig
    ) external onlyOwnerOrSystemAdmin {
        if (config.accessManager == address(0)) revert Errors.ZeroAddress();
        if (config.aam == address(0)) revert Errors.ZeroAddress();
        if (config.kvcmToken == address(0)) revert Errors.ZeroAddress();
        if (config.k2Token == address(0)) revert Errors.ZeroAddress();
        if (config.rewardManager == address(0)) revert Errors.ZeroAddress();
        if (config.maturityManager == address(0)) revert Errors.ZeroAddress();
        if (config.carbonLedger == address(0)) revert Errors.ZeroAddress();
        if (config.kvcmLocks == address(0)) revert Errors.ZeroAddress();
        if (config.kvcmLocksManager == address(0)) revert Errors.ZeroAddress();
        if (config.k2YieldToken == address(0)) revert Errors.ZeroAddress();
        if (config.retirementAggregator == address(0)) revert Errors.ZeroAddress();
        if (integrationConfig.zkMeCooperator == address(0)) revert Errors.ZeroAddress();
        if (integrationConfig.zkMeVerify == address(0)) revert Errors.ZeroAddress();
        if (integrationConfig.zkMeRequired == false) revert Errors.InvalidValue();

        StakingManagerStorage.StakingManagerConfigLayout storage l = StakingManagerStorage.configLayout();
        StakingManagerStorage.IntegrationConfigLayout storage i = StakingManagerStorage.integrationConfigLayout();
        l.accessManager = config.accessManager;
        l.aam = config.aam;
        l.kvcmToken = config.kvcmToken;
        l.k2Token = config.k2Token;
        l.rewardManager = config.rewardManager;
        l.maturityManager = config.maturityManager;
        l.carbonLedger = config.carbonLedger;
        l.kvcmLocks = config.kvcmLocks;
        l.kvcmLocksManager = config.kvcmLocksManager;
        l.k2YieldToken = config.k2YieldToken;
        l.retirementAggregator = config.retirementAggregator;
        i.zkMeCooperator = integrationConfig.zkMeCooperator;
        i.zkMeVerify = integrationConfig.zkMeVerify;
        i.zkMeRequired = integrationConfig.zkMeRequired;
        emit StakingManagerConfigurationUpdated(config, integrationConfig);
    }

    function setIntegrationConfiguration(StakingManagerStorage.IntegrationConfig memory integrationConfig)
        external
        onlyOwnerOrSystemAdmin
    {
        StakingManagerStorage.IntegrationConfigLayout storage i = StakingManagerStorage.integrationConfigLayout();
        i.zkMeCooperator = integrationConfig.zkMeCooperator;
        i.zkMeVerify = integrationConfig.zkMeVerify;
        i.zkMeRequired = integrationConfig.zkMeRequired;
        emit IntegrationConfigurationUpdated(integrationConfig);
    }

    // Setter functions

    function setAccessManager(address accessManager) external onlyOwnerOrSystemAdmin nonZero(accessManager) {
        StakingManagerStorage.configLayout().accessManager = accessManager;
        emit AccessManagerUpdated(accessManager);
    }

    function setAAM(address aam) external onlyOwnerOrSystemAdmin nonZero(aam) {
        StakingManagerStorage.configLayout().aam = aam;
        emit AAMUpdated(aam);
    }

    function setKvcmToken(address kvcmToken) external onlyOwnerOrSystemAdmin nonZero(kvcmToken) {
        StakingManagerStorage.configLayout().kvcmToken = kvcmToken;
        emit KvcmTokenUpdated(kvcmToken);
    }

    function setK2Token(address k2Token) external onlyOwnerOrSystemAdmin nonZero(k2Token) {
        StakingManagerStorage.configLayout().k2Token = k2Token;
        emit K2TokenUpdated(k2Token);
    }

    function setMaturityManager(address maturityManager) external onlyOwnerOrSystemAdmin nonZero(maturityManager) {
        StakingManagerStorage.configLayout().maturityManager = maturityManager;
        emit MaturityManagerUpdated(maturityManager);
    }

    function setKvcmLock(address kvcmLock) external onlyOwner {
        StakingManagerStorage.configLayout().kvcmLocks = kvcmLock;
        emit KvcmLockUpdated(kvcmLock);
    }

    function setRetirementAggregator(address retirementAggregator)
        external
        onlyOwnerOrSystemAdmin
        nonZero(retirementAggregator)
    {
        StakingManagerStorage.configLayout().retirementAggregator = retirementAggregator;
        emit RetirementAggregatorUpdated(retirementAggregator);
    }

    function setRewardManager(address rewardManager) external onlyOwnerOrSystemAdmin nonZero(rewardManager) {
        StakingManagerStorage.configLayout().rewardManager = rewardManager;
        emit RewardManagerUpdated(rewardManager);
    }

    function setCarbonLedger(address carbonLedger) external onlyOwnerOrSystemAdmin nonZero(carbonLedger) {
        StakingManagerStorage.configLayout().carbonLedger = carbonLedger;
        emit CarbonLedgerUpdated(carbonLedger);
    }

    function setZkMeCooperator(address zkMeCooperator) external onlyOwnerOrSystemAdmin nonZero(zkMeCooperator) {
        StakingManagerStorage.integrationConfigLayout().zkMeCooperator = zkMeCooperator;
        emit ZkMeCooperatorUpdated(zkMeCooperator);
    }

    function setZkMeVerify(address zkMeVerify) external onlyOwnerOrSystemAdmin nonZero(zkMeVerify) {
        StakingManagerStorage.integrationConfigLayout().zkMeVerify = zkMeVerify;
        emit ZkMeVerifyUpdated(zkMeVerify);
    }

    function setZkMeRequired(bool zkMeRequired) external onlyOwnerOrSystemAdmin {
        StakingManagerStorage.integrationConfigLayout().zkMeRequired = zkMeRequired;
        emit ZkMeRequiredUpdated(zkMeRequired);
    }

    function setK2LockLimits(uint256 minLockAmount, uint256 maxLockAmount) external onlyOwnerOrSystemAdmin {
        if (maxLockAmount < minLockAmount) revert Errors.InvalidAmounts(minLockAmount, maxLockAmount);

        StakingManagerStorage.k2StakingLayout().minLockAmount = SafeCast.toUint128(minLockAmount);
        StakingManagerStorage.k2StakingLayout().maxLockAmount = SafeCast.toUint128(maxLockAmount);
        emit LockAmountsUpdated(minLockAmount, maxLockAmount);
    }

    // @custom:note Debating whether to allow this. This would have implications for the length of the fixed LockedPrincipalInfo array.
    function setK2LockPeriod(uint256 minLockPeriod) external onlyOwnerOrSystemAdmin {
        StakingManagerStorage.k2StakingLayout().minLockPeriod = SafeCast.toUint128(minLockPeriod);
        emit K2LockPeriodUpdated(minLockPeriod);
    }

    // Getter functions

    function getAccessManager() external view returns (address) {
        return StakingManagerStorage.configLayout().accessManager;
    }

    function getAAM() external view returns (address) {
        return StakingManagerStorage.configLayout().aam;
    }

    function getKvcmToken() external view returns (address) {
        return StakingManagerStorage.configLayout().kvcmToken;
    }

    function getK2Token() external view returns (address) {
        return StakingManagerStorage.configLayout().k2Token;
    }

    function getMaturityManager() external view returns (address) {
        return StakingManagerStorage.configLayout().maturityManager;
    }

    function getRewardManager() external view returns (address) {
        return StakingManagerStorage.configLayout().rewardManager;
    }

    function getCarbonLedger() external view returns (address) {
        return StakingManagerStorage.configLayout().carbonLedger;
    }

    function getRetirementAggregator() external view returns (address) {
        return StakingManagerStorage.configLayout().retirementAggregator;
    }

    function getZkMeCooperator() external view returns (address) {
        return StakingManagerStorage.integrationConfigLayout().zkMeCooperator;
    }

    function getZkMeVerify() external view returns (address) {
        return StakingManagerStorage.integrationConfigLayout().zkMeVerify;
    }

    function getZkMeRequired() external view returns (bool) {
        return StakingManagerStorage.integrationConfigLayout().zkMeRequired;
    }

    function getK2LockLimits() external view returns (uint256 minLockAmount, uint256 maxLockAmount) {
        require(StakingManagerStorage.k2StakingLayout().minLockAmount != 0, "Min lock amount not set");
        require(StakingManagerStorage.k2StakingLayout().maxLockAmount != 0, "Max lock amount not set");

        minLockAmount = StakingManagerStorage.k2StakingLayout().minLockAmount;
        maxLockAmount = StakingManagerStorage.k2StakingLayout().maxLockAmount;
    }

    function getK2LockPeriod() external view returns (uint256) {
        return StakingManagerStorage.k2StakingLayout().minLockPeriod;
    }

    function getStakingManagerConfiguration()
        external
        view
        returns (
            StakingManagerStorage.StakingManagerConfig memory config,
            StakingManagerStorage.IntegrationConfig memory integrationConfig
        )
    {
        StakingManagerStorage.StakingManagerConfigLayout storage l = StakingManagerStorage.configLayout();
        StakingManagerStorage.IntegrationConfigLayout storage i = StakingManagerStorage.integrationConfigLayout();
        config = StakingManagerStorage.StakingManagerConfig({
            accessManager: l.accessManager,
            aam: l.aam,
            kvcmToken: l.kvcmToken,
            k2Token: l.k2Token,
            rewardManager: l.rewardManager,
            maturityManager: l.maturityManager,
            carbonLedger: l.carbonLedger,
            kvcmLocks: l.kvcmLocks,
            kvcmLocksManager: l.kvcmLocksManager,
            k2YieldToken: l.k2YieldToken,
            retirementAggregator: l.retirementAggregator
        });

        integrationConfig = StakingManagerStorage.IntegrationConfig({
            zkMeCooperator: i.zkMeCooperator, zkMeVerify: i.zkMeVerify, zkMeRequired: i.zkMeRequired
        });
        return (config, integrationConfig);
    }

    function getIntegrationConfiguration()
        external
        view
        returns (StakingManagerStorage.IntegrationConfig memory integrationConfig)
    {
        StakingManagerStorage.IntegrationConfigLayout storage i = StakingManagerStorage.integrationConfigLayout();
        integrationConfig = StakingManagerStorage.IntegrationConfig({
            zkMeCooperator: i.zkMeCooperator, zkMeVerify: i.zkMeVerify, zkMeRequired: i.zkMeRequired
        });
        return integrationConfig;
    }
}
