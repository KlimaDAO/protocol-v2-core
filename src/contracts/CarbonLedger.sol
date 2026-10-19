// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {
    ERC165Upgradeable,
    IERC165
} from "@openzeppelin-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {ICarbonLedger} from "../interfaces/ICarbonLedger.sol";
import {ICarbonClassVault} from "../interfaces/ICarbonClassVault.sol";
import {CarbonTonnageLib} from "../libraries/CarbonTonnageLib.sol";
import {CarbonLedgerStorage} from "../libraries/CarbonLedgerStorage.sol";
import {Errors} from "../libraries/Errors.sol";
import {CommonStructs} from "../libraries/CommonStructs.sol";
import {CarbonSystemRoleLib} from "../libraries/CarbonSystemRoleLib.sol";
import {ICommonEvents} from "../interfaces/ICommonEvents.sol";

/**
 * @title CarbonLedger
 * @dev A contract to manage carbon class vaults and their associated carbon credit tokens
 * Uses namespaced storage pattern for safer upgrades
 */
contract CarbonLedger is
    ICarbonLedger,
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ERC165Upgradeable,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;
    using CarbonTonnageLib for CommonStructs.ConversionConfig;

    // =============================================================
    //                           Constants
    // =============================================================

    uint256 private constant MAX_PRECISION = 1e18;
    uint256 private constant MIN_PRECISION = 1e6;

    // =============================================================
    //                            Modifiers
    // =============================================================

    /**
     * @dev Modifier to check if sender has admin or manager role
     */
    modifier onlyAdminOrManager() {
        _onlyAdminOrManager();
        _;
    }

    /**
     * @dev Modifier to check if sender has admin role only (most restrictive)
     */
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /**
     * @dev Modifier to check if sender has admin or liquidity manager role
     */
    modifier onlyAdminOrLiquidityManager() {
        _onlyAdminOrLiquidityManager();
        _;
    }

    /**
     * @dev Modifier to check if sender has maturity executor role (for automated jobs)
     */
    modifier onlyMaturityExecutor() {
        _onlyMaturityExecutor();
        _;
    }

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    // =============================================================
    //                  Constructor and Initializers
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param accessManager Address of the access manager contract
     */
    function initialize(address accessManager) public initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ERC165_init();

        if (accessManager == address(0)) {
            revert Errors.ZeroAddressNotAllowed();
        }

        // Store access manager and default max token IDs in config storage
        CarbonLedgerStorage.ConfigStorage storage config = CarbonLedgerStorage.getConfigStorage();
        config.accessManager = accessManager;
        config.maxTokenIdsPerMigration = 20; // Default value
        config.maxTokenIdsPerUnregister = 20; // Default value
    }

    // =============================================================
    //                   External View Functions
    // =============================================================

    function isSystemPaused() external view returns (bool) {
        return CarbonLedgerStorage.getConfigStorage().systemPaused;
    }

    /// @inheritdoc ICarbonLedger
    function getCreditDetails(address carbonCredit) external view override returns (CommonStructs.CreditConfig memory) {
        return CarbonLedgerStorage.getCreditRegistryStorage().creditConfigs[carbonCredit];
    }

    /// @inheritdoc ICarbonLedger
    function isClassRegistered(address classVault, bool shouldRevert) external view override returns (bool) {
        bool result = _isClassRegistered(classVault);

        if (shouldRevert) {
            if (!result) revert Errors.ClassNotRegistered(classVault);
        }

        return result;
    }

    /// @inheritdoc ICarbonLedger
    function isCreditRegisteredForClass(address classVault, address carbonCredit, bool shouldRevert)
        external
        view
        override
        returns (bool)
    {
        bool isClassValid = _isClassRegistered(classVault);
        bool isCreditValid = isClassValid && _isCreditRegisteredForClass(classVault, carbonCredit);

        if (shouldRevert) {
            if (!isClassValid) {
                revert Errors.ClassNotRegistered(classVault);
            } else if (!isCreditValid) {
                revert Errors.CarbonCreditNotRegisteredForClass(classVault, carbonCredit);
            }
        }

        return isCreditValid;
    }

    // =============================================================
    //                 External Functions - Class Management
    // =============================================================

    /// @inheritdoc ICarbonLedger
    function registerClass(address classVault) external override nonReentrant onlyAdminOrManager whenNotPaused {
        if (classVault == address(0)) {
            revert Errors.ZeroAddressClass();
        }

        CarbonLedgerStorage.ClassRegistryStorage storage classRegistryStorage =
            CarbonLedgerStorage.getClassRegistryStorage();

        if (_isClassRegistered(classVault)) {
            revert Errors.ClassNotInUnregisteredState(classVault);
        }

        // Verify it's a valid CarbonClassVault by checking if it implements the required interface
        try ICarbonClassVault(classVault).getClassVaultInfo() returns (string memory, address) {
            // Set status to Registered
            classRegistryStorage.carbonClassStatus[classVault] = CarbonLedgerStorage.Status.Registered;
            emit ClassVaultRegistered(classVault);
        } catch {
            revert Errors.InvalidClassVaultContract(classVault);
        }
    }

    /// @inheritdoc ICarbonLedger
    function unregisterClass(address classVault) external override nonReentrant onlyAdminOrManager whenNotPaused {
        CarbonLedgerStorage.ClassRegistryStorage storage classRegistryStorage =
            CarbonLedgerStorage.getClassRegistryStorage();

        if (!_isClassRegistered(classVault)) {
            revert Errors.ClassNotRegistered(classVault);
        }

        // Set status to Unregistered
        classRegistryStorage.carbonClassStatus[classVault] = CarbonLedgerStorage.Status.Unregistered;
        emit ClassVaultUnregistered(classVault);
    }

    // =============================================================
    //                External Functions - Credit Management
    // =============================================================

    /// @inheritdoc ICarbonLedger
    function registerCreditForClass(address classVault, address carbonCredit, uint256[] calldata tokenIds)
        external
        override
        onlyAdminOrManager
        whenNotPaused
    {
        if (carbonCredit == address(0)) {
            revert Errors.ZeroAddressClass();
        }

        CarbonLedgerStorage.CreditRegistryStorage storage creditRegistryStorage =
            CarbonLedgerStorage.getCreditRegistryStorage();
        CommonStructs.CreditConfig memory creditConfig = creditRegistryStorage.creditConfigs[carbonCredit];

        if (!_isClassRegistered(classVault)) {
            revert Errors.ClassNotRegistered(classVault);
        }

        if (!_isCreditRegisteredInLedger(carbonCredit)) {
            revert Errors.CarbonCreditNotRegisteredInLedger(carbonCredit);
        }

        // First call the vault to register the credit
        ICarbonClassVault(classVault).registerCarbonCredit(carbonCredit, tokenIds, creditConfig);

        // Then update the ledger state
        // Only set contract level status if it's not already registered
        if (
            creditRegistryStorage.creditStatusForClass[classVault][carbonCredit]
                != CarbonLedgerStorage.Status.Registered
        ) {
            creditRegistryStorage.creditStatusForClass[classVault][carbonCredit] = CarbonLedgerStorage.Status.Registered;
        }

        emit CreditRegisteredForClass(classVault, carbonCredit, tokenIds);
    }

    /// @inheritdoc ICarbonLedger
    function unregisterCreditForClass(address classVault, address carbonCredit, uint256[] calldata tokenIds)
        external
        override
        onlyAdminOrManager
        whenNotPaused
    {
        if (!_isCreditRegisteredForClass(classVault, carbonCredit)) {
            revert Errors.CarbonCreditNotRegisteredForClass(classVault, carbonCredit);
        }

        CarbonLedgerStorage.CreditRegistryStorage storage creditRegistryStorage =
            CarbonLedgerStorage.getCreditRegistryStorage();

        CommonStructs.CreditConfig memory creditConfig = creditRegistryStorage.creditConfigs[carbonCredit];

        // Handle based on token type
        if (creditConfig.tokenType == CommonStructs.TokenType.ERC20) {
            // For ERC20, we expect empty tokenIds array or just [0]
            if (tokenIds.length > 1 || (tokenIds.length == 1 && tokenIds[0] != 0)) {
                revert Errors.TokenIdMustBeZeroForERC20();
            }

            // Check if vault has any tokens before unregistering
            if (ICarbonClassVault(classVault).balanceCarbonCredits(carbonCredit, 0) > 0) {
                revert Errors.CarbonVaultHasCredits();
            }

            // Call vault to unregister the token
            ICarbonClassVault(classVault).unregisterCarbonCredit(carbonCredit, 0);

            // Set status to Unregistered for the credit token at contract level
            creditRegistryStorage.creditStatusForClass[classVault][carbonCredit] =
            CarbonLedgerStorage.Status.Unregistered;
        } else if (creditConfig.tokenType == CommonStructs.TokenType.ERC1155) {
            // For ERC1155, we require explicit tokenIds
            if (tokenIds.length == 0) {
                revert Errors.NoTokensSpecified();
            }

            // Enforce maximum array length to prevent DOS
            uint256 maxTokenIds = CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerUnregister;
            if (tokenIds.length > maxTokenIds) {
                revert Errors.TooManyTokenIds(tokenIds.length, maxTokenIds);
            }

            // Process each tokenId
            for (uint256 i = 0; i < tokenIds.length; i++) {
                uint256 tokenId = tokenIds[i];

                // Check if this specific tokenId has any balance
                if (ICarbonClassVault(classVault).balanceCarbonCredits(carbonCredit, tokenId) > 0) {
                    revert Errors.CarbonVaultHasCredits();
                }

                // Call vault to unregister this tokenId
                ICarbonClassVault(classVault).unregisterCarbonCredit(carbonCredit, tokenId);
            }

            // Only mark as Unregistered if no tokenIds remain in the vault
            uint256 remainingTokenIds = ICarbonClassVault(classVault).getRegisteredTokenIdsCount(carbonCredit);
            if (remainingTokenIds == 0) {
                creditRegistryStorage.creditStatusForClass[classVault][carbonCredit] =
                CarbonLedgerStorage.Status.Unregistered;
            }
        } else {
            revert Errors.InvalidTokenType();
        }

        emit CreditUnregisteredForClass(classVault, carbonCredit, tokenIds);
    }

    /// @inheritdoc ICarbonLedger
    function addCreditConfig(
        address carbonCredit,
        CommonStructs.TokenType tokenType,
        CommonStructs.ConversionConfig memory conversionConfig
    ) external override onlyAdminOrManager whenNotPaused {
        // Check if credit already exists
        if (_isCreditRegisteredInLedger(carbonCredit)) {
            revert Errors.CarbonCreditAlreadyExists(carbonCredit);
        }

        // Call internal function to set the info
        _setCreditConfig(carbonCredit, tokenType, conversionConfig);
    }

    /// @inheritdoc ICarbonLedger
    function updateCreditConfig(
        address carbonCredit,
        CommonStructs.TokenType tokenType,
        CommonStructs.ConversionConfig memory conversionConfig
    ) external override onlyAdminOrManager whenNotPaused {
        // Check if credit exists before updating
        if (!_isCreditRegisteredInLedger(carbonCredit)) {
            revert Errors.CarbonCreditNotRegisteredInLedger(carbonCredit);
        }

        // Call internal function to set the info
        _setCreditConfig(carbonCredit, tokenType, conversionConfig);
    }

    // =============================================================
    //              External Functions - Liquidity Management
    // =============================================================

    /// @inheritdoc ICarbonLedger
    function addCreditLiquidityToClassVault(
        address classVault,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        address from,
        uint256 amount,
        ICarbonClassVault.CouponBurnParams calldata couponBurn
    ) external override nonReentrant onlyAdminOrLiquidityManager {
        _addCreditLiquidityToClassVault(classVault, carbonCredit, tokenId, maturityId, from, amount, couponBurn);
    }

    /// @inheritdoc ICarbonLedger
    function removeCreditLiquidityFromClassVault(
        address classVault,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to,
        ICarbonClassVault.CouponBurnParams calldata couponBurn
    ) external override nonReentrant onlyAdminOrLiquidityManager {
        _removeCreditLiquidityFromClassVault(classVault, carbonCredit, tokenId, maturityId, amount, to, couponBurn);
    }

    // =============================================================
    //                External Functions - Migration
    // =============================================================

    /// @inheritdoc ICarbonLedger
    function migrateCreditBetweenClasses(
        address sourceVault,
        address targetVault,
        address carbonCredit,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external override onlyAdminOrManager nonReentrant {
        if (tokenIds.length == 0) revert Errors.NoTokensSpecified();
        if (tokenIds.length != amounts.length) revert Errors.ArraysLengthMismatch();

        // Prevent circular migration
        if (sourceVault == targetVault) {
            revert Errors.SourceAndTargetVaultCannotBeSame(sourceVault);
        }

        // Check if both vaults are registered
        if (!_isClassRegistered(sourceVault)) {
            revert Errors.ClassNotRegistered(sourceVault);
        }
        if (!_isClassRegistered(targetVault)) {
            revert Errors.ClassNotRegistered(targetVault);
        }

        // Check if credit is registered in both vaults
        if (!_isCreditRegisteredForClass(sourceVault, carbonCredit)) {
            revert Errors.CarbonCreditNotRegisteredForClass(sourceVault, carbonCredit);
        }
        if (!_isCreditRegisteredForClass(targetVault, carbonCredit)) {
            revert Errors.CarbonCreditNotRegisteredForClass(targetVault, carbonCredit);
        }

        CommonStructs.CreditConfig memory creditConfig =
            CarbonLedgerStorage.getCreditRegistryStorage().creditConfigs[carbonCredit];

        // Handle based on token type
        if (creditConfig.tokenType == CommonStructs.TokenType.ERC20) {
            // For ERC20, tokenId is always 0 and we can process as a single call
            if (tokenIds.length != 1 || amounts.length != 1) {
                revert Errors.ArraysLengthMismatch();
            }

            if (tokenIds[0] != 0) {
                revert Errors.TokenIdMustBeZeroForERC20();
            }

            // Simple migration for ERC20
            uint256 amount = amounts[0];
            if (amount == 0) {
                revert Errors.AmountCannotBeZero();
            }

            // Migration flow:
            // 1. Withdraw from Source Vault to this contract (CarbonLedger)
            ICarbonClassVault(sourceVault)
                .withdrawCarbonCredits(
                    carbonCredit,
                    0,
                    0,
                    amount,
                    address(this),
                    ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
                );

            // 2. Approve target vault to pull tokens from CarbonLedger
            IERC20(carbonCredit).approve(targetVault, amount);

            // 3. Deposit to Target Vault
            ICarbonClassVault(targetVault)
                .depositCarbonCredits(
                    carbonCredit,
                    0,
                    0,
                    address(this),
                    amount,
                    ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
                );

            // Emit event
            emit CreditsMigratedBetweenClasses(sourceVault, targetVault, carbonCredit, amount, 0);
        } else if (creditConfig.tokenType == CommonStructs.TokenType.ERC1155) {
            // For ERC1155, we need to ensure the tokenIds array is proper
            if (tokenIds.length == 0 || tokenIds.length != amounts.length) {
                revert Errors.ArraysLengthMismatch();
            }

            // Enforce maximum array length
            uint256 maxTokenIds = CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerMigration;
            if (tokenIds.length > maxTokenIds) {
                revert Errors.TooManyTokenIds(tokenIds.length, maxTokenIds);
            }

            // Check for duplicate tokenIds
            for (uint256 i = 0; i < tokenIds.length; i++) {
                for (uint256 j = i + 1; j < tokenIds.length; j++) {
                    if (tokenIds[i] == tokenIds[j]) {
                        revert Errors.DuplicateTokenIdsInArray(tokenIds[i]);
                    }
                }
            }

            // Approve target vault to pull ERC1155 tokens from CarbonLedger
            IERC1155(carbonCredit).setApprovalForAll(targetVault, true);

            // Process each tokenId
            for (uint256 i = 0; i < tokenIds.length; i++) {
                uint256 tokenId = tokenIds[i];
                uint256 amount = amounts[i];

                if (amount == 0) {
                    revert Errors.AmountCannotBeZero();
                }

                // 1. Withdraw from Source Vault to this contract
                ICarbonClassVault(sourceVault)
                    .withdrawCarbonCredits(
                        carbonCredit,
                        tokenId,
                        0,
                        amount,
                        address(this),
                        ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
                    );

                // 2. Deposit to Target Vault
                ICarbonClassVault(targetVault)
                    .depositCarbonCredits(
                        carbonCredit,
                        tokenId,
                        0,
                        address(this),
                        amount,
                        ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
                    );

                // Emit event for this migration
                emit CreditsMigratedBetweenClasses(sourceVault, targetVault, carbonCredit, amount, tokenId);
            }

            // Revoke approval after migration is complete
            IERC1155(carbonCredit).setApprovalForAll(targetVault, false);
        } else {
            revert Errors.InvalidTokenType();
        }
    }

    // =============================================================
    //                External Functions - Dust Removal
    // =============================================================

    /**
     * @dev [Admin Only] Recovers ERC20 tokens that were sent directly to the Ledger contract address.
     *      This function transfers the entire balance of the specified ERC20 token
     *      held by the Ledger contract itself to a designated address.
     * @param tokenAddress The address of the ERC20 token to recover.
     * @param to The address to send the recovered tokens to.
     */
    function removeDust(address tokenAddress, address to) external nonReentrant onlyAdminOrManager whenNotPaused {
        if (to == address(0)) revert Errors.ZeroAddressNotAllowed();
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance > 0) {
            IERC20(tokenAddress).safeTransfer(to, balance);
        }
    }

    /**
     * @dev [Admin Only] Recovers ERC1155 tokens that were sent directly to the Ledger contract address.
     *      This function transfers the entire balance of the specified ERC1155 token ID
     *      held by the Ledger contract itself to a designated address.
     * @param tokenAddress The address of the ERC1155 token contract.
     * @param tokenId The ID of the token to recover.
     * @param to The address to send the recovered tokens to.
     */
    function removeDustERC1155(address tokenAddress, uint256 tokenId, address to)
        external
        nonReentrant
        onlyAdminOrManager
    {
        if (to == address(0)) revert Errors.ZeroAddressNotAllowed();
        uint256 balance = IERC1155(tokenAddress).balanceOf(address(this), tokenId);
        if (balance > 0) {
            // Requires Ledger to be approved or operator for itself? This might need review depending on token implementation.
            // Assuming direct transfer is possible for tokens held by the contract.
            IERC1155(tokenAddress).safeTransferFrom(address(this), to, tokenId, balance, "");
        }
    }

    /**
     * @dev [Admin Only] Emergency function to remove liquidity from a class vault.
     *      Bypasses class and credit registration checks, allowing withdrawal even when:
     *      - Class vault is unregistered
     *      - Credit is unregistered for the class
     *      Use case: Recovering funds from an unregistered class vault.
     * @param classVault The address of the class vault to withdraw from.
     * @param carbonCredit The address of the carbon credit token.
     * @param tokenId The token ID (for ERC1155, 0 for ERC20).
     * @param maturityId The maturity ID (0 for liquid carbon).
     * @param amount The amount of tokens to withdraw.
     * @param to The address to send the tokens to.
     */
    function emergencyRemoveLiquidity(
        address classVault,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to
    ) external nonReentrant onlyAdmin whenNotPaused {
        if (to == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (amount == 0) revert Errors.AmountCannotBeZero();

        // Bypass registration checks - directly call vault withdrawal
        ICarbonClassVault(classVault)
            .withdrawCarbonCredits(
                carbonCredit,
                tokenId,
                maturityId,
                amount,
                to,
                ICarbonClassVault.CouponBurnParams({tonnes: 0, from: address(0)})
            );

        emit EmergencyLiquidityRemoved(classVault, carbonCredit, to, amount, tokenId, maturityId);
    }

    function executeMatureForwardCarbon(address classVault, uint256 maturityId)
        external
        onlyMaturityExecutor
        whenNotPaused
    {
        ICarbonClassVault(classVault).matureForwardCarbon(maturityId);
    }

    /**
     * @notice Matures forward carbon for a specific maturity ID in batches
     * @dev Allows processing a subset of tokens per transaction to avoid gas limits
     * @param classVault Address of the class vault to mature forward carbon in
     * @param maturityId The maturity ID to mature forward carbon for
     * @param erc20Tokens Array of ERC20 token addresses to process
     * @param erc1155Tokens Array of ERC1155 token addresses to process
     * @param erc1155TokenIds Array of token ID arrays corresponding to each ERC1155 token
     */
    function executeMatureForwardCarbonBatch(
        address classVault,
        uint256 maturityId,
        address[] calldata erc20Tokens,
        address[] calldata erc1155Tokens,
        uint256[][] calldata erc1155TokenIds
    ) external onlyMaturityExecutor whenNotPaused {
        ICarbonClassVault(classVault).matureForwardCarbonBatch(maturityId, erc20Tokens, erc1155Tokens, erc1155TokenIds);
    }

    // =============================================================
    //               External Functions - Access Management
    // =============================================================

    /**
     * @dev Sets a new access manager for the ledger
     * @param newAccessManager The address of the new access manager
     * @notice Only callable by an address with the appropriate permissions in the current access manager
     */
    function setAccessManager(address newAccessManager) external override onlyAdminOrManager {
        if (newAccessManager == address(0)) {
            revert Errors.ZeroAddressNotAllowed();
        }

        CarbonLedgerStorage.getConfigStorage().accessManager = newAccessManager;

        emit AccessManagerUpdated(newAccessManager);
    }

    /**
     * @dev Sets the maximum number of tokenIds allowed per migration
     * @param newMax The new maximum number of tokenIds
     * @notice Only callable by admin
     */
    function setMaxTokenIdsPerMigration(uint256 newMax) external onlyAdminOrManager {
        if (newMax == 0) {
            revert Errors.InvalidMaxTokenIds();
        }

        uint256 oldMax = CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerMigration;
        CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerMigration = newMax;

        emit MaxTokenIdsPerMigrationUpdated(oldMax, newMax);
    }

    /**
     * @dev Sets the maximum number of tokenIds allowed per unregister call
     * @param newMax The new maximum number of tokenIds
     * @notice Only callable by admin
     */
    function setMaxTokenIdsPerUnregister(uint256 newMax) external onlyAdminOrManager {
        if (newMax == 0) {
            revert Errors.InvalidMaxTokenIds();
        }

        uint256 oldMax = CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerUnregister;
        CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerUnregister = newMax;

        emit MaxTokenIdsPerUnregisterUpdated(oldMax, newMax);
    }

    // =============================================================
    //                  Public View Functions
    // =============================================================

    /**
     * @dev Returns the current access manager address
     * @return address Access manager contract address
     */
    function getAccessManager() public view override returns (address) {
        return CarbonLedgerStorage.getConfigStorage().accessManager;
    }

    /**
     * @dev Returns the maximum number of tokenIds allowed per migration
     * @return uint256 Maximum number of tokenIds
     */
    function getMaxTokenIdsPerMigration() external view returns (uint256) {
        return CarbonLedgerStorage.getConfigStorage().maxTokenIdsPerMigration;
    }

    /**
     * @dev Override supportsInterface function to fix multiple inheritance
     * @param interfaceId Interface ID to check
     * @return True if interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(ICarbonLedger).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // =============================================================
    //                  Public Functions
    // =============================================================

    /**
     * @dev Handles the receipt of a single ERC1155 token type.
     * This function is called at the end of a `safeTransferFrom` after the balance has been updated.
     * To accept the transfer, this must return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`.
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     */
    function onERC1155Received(
        address, /* operator */
        address, /* from */
        uint256, /* id */
        uint256, /* value */
        bytes calldata /* data */
    )
        public
        virtual
        override
        returns (bytes4)
    {
        // By returning the selector, we confirm the contract can receive ERC1155 tokens.
        // No specific action needed by the Ledger itself upon receiving.
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of multiple ERC1155 token types.
     * This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated.
     * To accept the transfer(s), this must return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`.
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     */
    function onERC1155BatchReceived(
        address, /* operator */
        address, /* from */
        uint256[] calldata, /* ids */
        uint256[] calldata, /* values */
        bytes calldata /* data */
    )
        public
        virtual
        override
        returns (bytes4)
    {
        // By returning the selector, we confirm the contract can receive ERC1155 tokens.
        // No specific action needed by the Ledger itself upon receiving.
        return this.onERC1155BatchReceived.selector;
    }

    // =============================================================
    //                    Internal Functions
    // =============================================================

    /**
     * @dev Required override for UUPS upgrade authorization
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdminOrManager {}

    /**
     * @dev Internal function for onlyAdminOrManager modifier
     */
    function _onlyAdminOrManager() internal view {
        address accessManager = getAccessManager();

        (bool hasLedgerAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_LEDGER_ADMIN, msg.sender);
        (bool hasLedgerManagerRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_LEDGER_MANAGER, msg.sender);

        if (!hasLedgerAdminRole && !hasLedgerManagerRole) {
            revert Errors.CallerNotAdminOrManager();
        }
    }

    /**
     * @dev Internal function for onlyAdmin modifier (admin only, most restrictive)
     */
    function _onlyAdmin() internal view {
        address accessManager = getAccessManager();

        (bool hasLedgerAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_LEDGER_ADMIN, msg.sender);

        if (!hasLedgerAdminRole) {
            revert Errors.CallerNotAdmin();
        }
    }

    /**
     * @dev Internal function for onlyAdminOrLiquidityManager modifier
     */
    function _onlyAdminOrLiquidityManager() internal view {
        address accessManager = getAccessManager();

        (bool hasLedgerAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_LEDGER_ADMIN, msg.sender);
        (bool hasLiquidityManagerRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_LIQUIDITY_MANAGER, msg.sender);

        if (!hasLedgerAdminRole && !hasLiquidityManagerRole) {
            revert Errors.CallerNotAdminOrLiquidityManager();
        }
    }

    /**
     * @dev Internal function for onlyMaturityExecutor modifier (allows both dedicated executor role and admin)
     */
    function _onlyMaturityExecutor() internal view {
        address accessManager = getAccessManager();

        (bool hasMaturityExecutorRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_MATURITY_EXECUTOR, msg.sender);
        (bool hasLedgerAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_LEDGER_ADMIN, msg.sender);

        if (!hasMaturityExecutorRole && !hasLedgerAdminRole) {
            revert Errors.CallerNotMaturityExecutor();
        }
    }

    /**
     * @dev Internal function for whenNotPaused modifier
     */
    function _whenNotPaused() internal view {
        if (CarbonLedgerStorage.getConfigStorage().systemPaused) {
            revert Errors.SystemPaused();
        }
    }

    /**
     * @dev Internal logic for adding credit liquidity to a class vault.
     * @param classVault Address of the class vault
     * @param carbonCredit Address of the credit token
     * @param from Address providing the liquidity
     * @param amount Amount of tokens to add
     * @param tokenId Token ID for ERC1155 tokens
     * @param couponBurn Parameters for burning coupons during deposit
     */
    function _addCreditLiquidityToClassVault(
        address classVault,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        address from,
        uint256 amount,
        ICarbonClassVault.CouponBurnParams memory couponBurn
    ) internal {
        _validateLiquidityOperation(classVault, carbonCredit, amount);
        ICarbonClassVault(classVault).depositCarbonCredits(carbonCredit, tokenId, maturityId, from, amount, couponBurn);
        emit CreditLiquidityAddedToClassVault(classVault, carbonCredit, from, amount, tokenId);
    }

    /**
     * @dev Internal logic for removing credit liquidity from a class vault.
     * @param carbonClass Address of the class vault
     * @param carbonCredit Address of the credit token
     * @param tokenId Token ID for ERC1155 tokens
     * @param amount Amount of tokens to remove
     * @param to Address to send the withdrawn tokens to
     * @param couponBurn Parameters for burning coupons during withdrawal
     */
    function _removeCreditLiquidityFromClassVault(
        address carbonClass,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to,
        ICarbonClassVault.CouponBurnParams memory couponBurn
    ) internal {
        _validateLiquidityOperation(carbonClass, carbonCredit, amount);
        ICarbonClassVault(carbonClass).withdrawCarbonCredits(carbonCredit, tokenId, maturityId, amount, to, couponBurn);
        emit CreditLiquidityRemovedFromClassVault(carbonClass, carbonCredit, to, amount, tokenId);
    }

    /**
     * @dev Internal helper to validate common conditions for liquidity operations.
     * Ensures class & credit are registered, amount > 0, and credit is recognized.
     * @param carbonClass Address of the class vault
     * @param carbonCredit Address of the credit token
     * @param amount Amount of tokens involved
     */
    function _validateLiquidityOperation(address carbonClass, address carbonCredit, uint256 amount) internal view {
        if (amount == 0) {
            revert Errors.AmountCannotBeZero();
        }

        // Check class is registered
        if (!_isClassRegistered(carbonClass)) {
            revert Errors.ClassNotRegistered(carbonClass);
        }

        // Check credit is registered for the class
        if (!_isCreditRegisteredForClass(carbonClass, carbonCredit)) {
            revert Errors.CarbonCreditNotRegisteredForClass(carbonClass, carbonCredit);
        }
    }

    /**
     * @dev Internal logic to set or update the information for a specific credit token.
     * @param tokenType Type of the token (ERC20/ERC1155)
     * @param carbonCredit Address of the credit token
     * @param conversionConfig Configuration for unit conversion
     */
    function _setCreditConfig(
        address carbonCredit,
        CommonStructs.TokenType tokenType,
        CommonStructs.ConversionConfig memory conversionConfig
    ) internal {
        if (carbonCredit == address(0)) {
            revert Errors.ZeroAddressClass();
        }

        if (tokenType != CommonStructs.TokenType.ERC20 && tokenType != CommonStructs.TokenType.ERC1155) {
            revert Errors.InvalidTokenType();
        }

        // Validate the configuration using the library
        if (!CarbonTonnageLib.isValidConversionConfig(conversionConfig)) {
            revert Errors.InvalidConversionConfig();
        }

        // Store the credit information
        CarbonLedgerStorage.getCreditRegistryStorage().creditConfigs[carbonCredit] = CommonStructs.CreditConfig({
            tokenType: tokenType, conversion: conversionConfig, tokenAddress: carbonCredit
        });

        emit CreditConfigSet(carbonCredit, tokenType, conversionConfig);
    }

    function _isClassRegistered(address classVault) internal view returns (bool) {
        return CarbonLedgerStorage.getClassRegistryStorage().carbonClassStatus[classVault]
            == CarbonLedgerStorage.Status.Registered;
    }

    function _isCreditRegisteredInLedger(address carbonCredit) internal view returns (bool) {
        return CarbonLedgerStorage.getCreditRegistryStorage().creditConfigs[carbonCredit].tokenAddress != address(0);
    }

    function _isCreditRegisteredForClass(address classVault, address carbonCredit) internal view returns (bool) {
        return CarbonLedgerStorage.getCreditRegistryStorage().creditStatusForClass[classVault][carbonCredit]
            == CarbonLedgerStorage.Status.Registered;
    }

    // Pause/Unpause

    function pauseCarbonLedger() external onlyAdminOrManager {
        CarbonLedgerStorage.getConfigStorage().systemPaused = true;
        emit ICommonEvents.SystemPauseStatusChanged(true);
    }

    function unpauseCarbonLedger() external onlyAdminOrManager {
        CarbonLedgerStorage.getConfigStorage().systemPaused = false;
        emit ICommonEvents.SystemPauseStatusChanged(false);
    }

    // TODO [26-05-2025]:
    // Let's add an override for Withdraw where registration is skipped.. ()
    // LLet's add pause/unpause here ? : Pausing will remove tonnes from class -> and later on token-token_Id pair
}
