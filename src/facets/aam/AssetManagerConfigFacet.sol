// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// libraries
import "../../libraries/LibDiamond.sol";
import "../../libraries/storage/AssetManagerStorage.sol";
import "../../libraries/Errors.sol";
import "../../libraries/CarbonSystemRoleLib.sol";
// interfaces
import {IAssetManagerConfigFacet} from "../../interfaces/AssetManager/IAssetManagerConfigFacet.sol";
import {ICommonEvents} from "../../interfaces/ICommonEvents.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

/**
 * @title AssetManagerConfigFacet
 * @notice Facet that manages global configuration for the Kvcm Asset Manager
 */
contract AssetManagerConfigFacet is ICommonEvents, IAssetManagerConfigFacet {
    /* ─────────────── Modifiers ────────────── */

    modifier onlyOwnerOrSystemAdmin() {
        (bool hasRole,) = IAccessManager(AssetManagerStorage.configLayout().aamConfig.accessManager)
            .hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (msg.sender != LibDiamond.contractOwner() && !hasRole) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != LibDiamond.contractOwner()) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    modifier nonZero(address value) {
        if (value == address(0)) revert Errors.ZeroAddress();
        _;
    }

    function initialize(address _accessManager) external onlyOwner nonZero(_accessManager) {
        bool initialized = AssetManagerStorage.configLayout().initialized;
        if (initialized) {
            revert Errors.AlreadyInitialized();
        }

        _initAccessManager(_accessManager);

        AssetManagerStorage.configLayout().initialized = true;
    }

    /* --- Access manager --- */
    /// One-time initializer

    function _initAccessManager(address _accessManager) internal onlyOwner nonZero(_accessManager) {
        if (AssetManagerStorage.configLayout().aamConfig.accessManager != address(0)) {
            revert Errors.AlreadyInitialized();
        }

        AssetManagerStorage.configLayout().aamConfig.accessManager = _accessManager;
        emit AccessManagerUpdated(_accessManager);
    }

    /* ───────────── External ─────────── */

    /* --- System-wide pause flag --- */
    function setSystemPaused(bool paused) external onlyOwnerOrSystemAdmin {
        AssetManagerStorage.configLayout().systemPaused = paused;
        emit SystemPauseStatusChanged(paused);
    }

    function isSystemPaused() external view returns (bool) {
        return AssetManagerStorage.configLayout().systemPaused;
    }

    /* --- Global Configuration --- */

    function setConfiguration(AssetManagerStorage.AssetManagerConfig memory config) external onlyOwnerOrSystemAdmin {
        // verify each address is not zero address
        // Verify each address is not zero address
        if (config.accessManager == address(0)) revert Errors.ZeroAddress();
        if (config.kvcm == address(0)) revert Errors.ZeroAddress();
        if (config.protocolSupplyOracle == address(0)) revert Errors.ZeroAddress();
        if (config.protocolMinter == address(0)) revert Errors.ZeroAddress();
        if (config.maturityManager == address(0)) revert Errors.ZeroAddress();
        if (config.stakingManager == address(0)) revert Errors.ZeroAddress();
        if (config.rewardManager == address(0)) revert Errors.ZeroAddress();
        if (config.carbonLedger == address(0)) revert Errors.ZeroAddress();
        if (config.retirementAggregator == address(0)) revert Errors.ZeroAddress();

        AssetManagerStorage.configLayout().aamConfig = config;
        emit AssetManagerConfigurationUpdated(config);
    }

    function getConfiguration() external view returns (AssetManagerStorage.AssetManagerConfig memory) {
        return AssetManagerStorage.configLayout().aamConfig;
    }
    /* --- Individual Configuration --- */

    function setAccessManager(address _accessManager) external onlyOwnerOrSystemAdmin nonZero(_accessManager) {
        AssetManagerStorage.configLayout().aamConfig.accessManager = _accessManager;
        emit AccessManagerUpdated(_accessManager);
    }

    function getAccessManager() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.accessManager;
    }

    /* --- KVCM token address --- */
    function setKvcmToken(address _kvcm) external onlyOwnerOrSystemAdmin nonZero(_kvcm) {
        AssetManagerStorage.configLayout().aamConfig.kvcm = _kvcm;
        emit KvcmTokenUpdated(_kvcm);
    }

    function getKvcmToken() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.kvcm;
    }

    /* --- ProtocolSupplyOracle --- */
    function setProtocolSupplyOracle(address _protocolSupplyOracle)
        external
        onlyOwnerOrSystemAdmin
        nonZero(_protocolSupplyOracle)
    {
        AssetManagerStorage.configLayout().aamConfig.protocolSupplyOracle = _protocolSupplyOracle;
        emit ProtocolSupplyOracleUpdated(_protocolSupplyOracle);
    }

    function getProtocolSupplyOracle() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.protocolSupplyOracle;
    }

    /* --- StakingManager --- */
    function setStakingManager(address _stakingManager) external onlyOwnerOrSystemAdmin nonZero(_stakingManager) {
        AssetManagerStorage.configLayout().aamConfig.stakingManager = _stakingManager;
        emit StakingManagerUpdated(_stakingManager);
    }

    function getStakingManager() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.stakingManager;
    }

    /* --- CarbonLedger --- */
    function setCarbonLedger(address _carbonLedger) external onlyOwnerOrSystemAdmin nonZero(_carbonLedger) {
        AssetManagerStorage.configLayout().aamConfig.carbonLedger = _carbonLedger;
        emit CarbonLedgerUpdated(_carbonLedger);
    }

    function getCarbonLedger() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.carbonLedger;
    }

    /* --- RewardManager --- */
    function setRewardManager(address _rewardManager) external onlyOwnerOrSystemAdmin nonZero(_rewardManager) {
        AssetManagerStorage.configLayout().aamConfig.rewardManager = _rewardManager;
        emit RewardManagerUpdated(_rewardManager);
    }

    function getRewardManager() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.rewardManager;
    }

    /* --- MaturityManager --- */
    function setMaturityManager(address _maturityManager) external onlyOwnerOrSystemAdmin nonZero(_maturityManager) {
        AssetManagerStorage.configLayout().aamConfig.maturityManager = _maturityManager;
        emit MaturityManagerUpdated(_maturityManager);
    }

    function getMaturityManager() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.maturityManager;
    }

    /* --- RetirementAggregator --- */

    function setRetirementAggregator(address _retirementAggregator)
        external
        onlyOwnerOrSystemAdmin
        nonZero(_retirementAggregator)
    {
        AssetManagerStorage.configLayout().aamConfig.retirementAggregator = _retirementAggregator;
        emit RetirementAggregatorUpdated(_retirementAggregator);
    }

    function getRetirementAggregator() external view returns (address) {
        return AssetManagerStorage.configLayout().aamConfig.retirementAggregator;
    }

    /* --- lastUpdateTimestamp --- */

    function updateLastUpdateTimestamp(address carbonClass) external onlyOwnerOrSystemAdmin {
        AssetManagerStorage.classQuoterLayout().quoters[carbonClass].lastUpdateTimestamp = block.timestamp;
    }

    function getLastUpdateTimestamp(address carbonClass) external view returns (uint256) {
        return AssetManagerStorage.classQuoterLayout().quoters[carbonClass].lastUpdateTimestamp;
    }
}
