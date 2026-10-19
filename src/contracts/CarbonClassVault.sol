// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============== Imports ==============
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {ICarbonClassVault} from "../interfaces/ICarbonClassVault.sol";
import {ICarbonLedger} from "../interfaces/ICarbonLedger.sol";
import {ICarbonClassCoupons} from "../interfaces/ICarbonClassCoupons.sol";
import {IMaturityManager} from "../interfaces/IMaturityManager.sol";
import {CarbonVaultStorage} from "../libraries/CarbonVaultStorage.sol";
import {CarbonTonnageLib} from "../libraries/CarbonTonnageLib.sol";
import {Errors} from "../libraries/Errors.sol";
import {CommonStructs} from "../libraries/CommonStructs.sol";
import {ClassVaultRegistrationUtilsLib} from "../libraries/ClassVaultRegistrationUtilsLib.sol";
import {CarbonSystemRoleLib} from "../libraries/CarbonSystemRoleLib.sol";
import {CarbonClassCoupons} from "./CarbonClassCoupons.sol";
import {ClassVaultRegistrationManager} from "./ClassVaultRegistrationManager.sol";

/**
 * @title CarbonClassVault
 * @dev A vault for storing carbon credit tokens (ERC20 and ERC1155) for a specific carbon class.
 *      It tracks the total equivalent carbon tonnes represented by the deposited tokens.
 *      Uses namespaced storage for better organization and upgradability.
 *      Includes a coupon system for tokenizing carbon tonnes.
 *
 * @notice This contract uses the UUPS upgradeable pattern and should be deployed behind a proxy.
 *      Do not use the constructor for initialization, use the initialize function instead.
 */
contract CarbonClassVault is
    ICarbonClassVault,
    ERC165Upgradeable,
    ReentrancyGuardUpgradeable,
    CarbonClassCoupons,
    IERC1155Receiver,
    UUPSUpgradeable
{
    // ============== Using Statements ==============
    using SafeERC20 for IERC20;
    using CarbonTonnageLib for CommonStructs.ConversionConfig;
    using CarbonVaultStorage for CarbonVaultStorage.VaultConfigStorage;
    using CarbonVaultStorage for CarbonVaultStorage.TokenManagementStorage;
    using CarbonVaultStorage for CarbonVaultStorage.VaultAccountingStorage;

    // ============== State Variables ==============
    /**
     * @dev Version of the contract initialization
     * Used to ensure the implementation has been initialized at least once
     */
    uint8 private constant CONTRACT_VERSION = 1;

    // ============== Modifiers ==============
    /**
     * @dev Modifier to check if the sender is the CarbonLedger contract
     */
    modifier onlyCarbonLedger() {
        _onlyCarbonLedger();
        _;
    }

    /**
     * @dev Modifier for functions that should only be called by addresses with appropriate role
     */
    modifier onlySystemAdmin() {
        _onlySystemAdmin();
        _;
    }

    // ============== Constructor ==============
    /**
     * @dev Constructor
     * Empty constructor for upgradeable contracts. No initialization happens here.
     * All initialization happens in the initialize function.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable direct initialization of the implementation contract
        _disableInitializers();
    }

    // ============== External Functions - State Changing ==============
    /**
     * @dev Initializes the contract for use with a proxy
     * @param vaultParams Struct containing vault configuration parameters
     */
    function initialize(VaultConfigInitParams memory vaultParams) external initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ERC165_init();
        __CarbonClassCoupons_init(vaultParams.name, vaultParams.symbol);

        // Initialize our own storage
        CarbonVaultStorage.VaultConfigStorage storage vaultConfig = CarbonVaultStorage.getVaultConfigStorage();
        vaultConfig.name = vaultParams.name;
        vaultConfig.carbonLedger = vaultParams.carbonLedger;
        vaultConfig.accessManager = vaultParams.accessManager;
        vaultConfig.maturityManager = vaultParams.maturityManager;
        vaultConfig.registrationManager = vaultParams.registrationManager;
    }

    /**
     * @dev Register a carbon credit token for use with this vault
     * @param creditToken Address of the carbon credit token to register
     * @param tokenIds Array of token IDs to register (for ERC1155 tokens, empty or [0] for ERC20)
     * @param creditConfig carbon credit configuration info
     */
    function registerCarbonCredit(
        address creditToken,
        uint256[] calldata tokenIds,
        CommonStructs.CreditConfig calldata creditConfig
    ) external override onlyCarbonLedger nonReentrant returns (bool) {
        address registrationManager = CarbonVaultStorage.getVaultConfigStorage().registrationManager;

        if (registrationManager == address(0)) {
            // Revert if no registration manager is set - we're removing the library fallback
            revert Errors.NotAuthorized();
        }

        // Use delegatecall to the registration manager
        (bool success, bytes memory returnData) = registrationManager.delegatecall(
            abi.encodeWithSelector(
                ClassVaultRegistrationManager.registerCarbonCredit.selector, creditToken, tokenIds, creditConfig
            )
        );

        // Handle delegatecall results
        if (!success) {
            // If the call fails, extract the revert reason if possible
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert Errors.RegistrationFailed();
            }
        }

        bool registrationSuccess = abi.decode(returnData, (bool));

        if (!registrationSuccess) {
            revert Errors.RegistrationFailed();
        }

        return registrationSuccess;
    }

    /**
     * @dev Unregister a carbon credit tokenId from this vault
     * @param creditToken Address of the credit token to unregister
     * @param tokenId The token ID to unregister
     */
    function unregisterCarbonCredit(address creditToken, uint256 tokenId) external onlyCarbonLedger nonReentrant {
        address registrationManager = CarbonVaultStorage.getVaultConfigStorage().registrationManager;

        // Get token type from CarbonLedger
        CommonStructs.CreditConfig memory config = ICarbonLedger(carbonLedger()).getCreditDetails(creditToken);

        if (registrationManager == address(0)) {
            // Revert if no registration manager is set - we're removing the library fallback
            revert Errors.NotAuthorized();
        }

        // Use delegatecall to the registration manager
        (bool success, bytes memory returnData) = registrationManager.delegatecall(
            abi.encodeWithSelector(
                ClassVaultRegistrationManager.unregisterCarbonCredit.selector, creditToken, tokenId, config.tokenType
            )
        );

        // Handle delegatecall results
        if (!success) {
            // If the call fails, extract the revert reason if possible
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert Errors.UnregistrationFailed();
            }
        }
    }

    /**
     * @dev Sets the registration manager address
     * @param _registrationManager Address of the registration manager contract
     */
    function setRegistrationManager(address _registrationManager) external onlySystemAdmin {
        if (_registrationManager == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (_registrationManager.code.length == 0) revert Errors.NoCodeAtAddress(_registrationManager);
        CarbonVaultStorage.getVaultConfigStorage().registrationManager = _registrationManager;

        emit RegistrationManagerUpdated(_registrationManager);
    }

    /**
     * @dev Deposit carbon credits into the vault
     * @param carbonCredit Address of the credit token
     * @param tokenId Token ID (for ERC1155 tokens... for ERC20 tokens, this is 0)
     * @param maturityId ID of the maturity for tracking forward carbons
     * @param from Address to pull tokens from
     * @param amount Amount of tokens to deposit
     * @param couponBurn Parameters for burning coupons during deposit (optional)
     */
    function depositCarbonCredits(
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        address from,
        uint256 amount,
        ICarbonClassVault.CouponBurnParams calldata couponBurn
    ) external virtual override onlyCarbonLedger nonReentrant {
        // Call the internal function
        _depositCredits(carbonCredit, tokenId, maturityId, from, amount, couponBurn);
    }

    /**
     * @dev Withdraw carbon credits directly without checking registration
     * @param carbonCredit Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @param maturityId ID of the maturity to withdraw from (0 for liquid carbon)
     * @param amount Amount of tokens to withdraw
     * @param to Address to send the tokens to
     * @param couponBurn Parameters for burning coupons during withdrawal
     */
    function withdrawCarbonCredits(
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to,
        ICarbonClassVault.CouponBurnParams calldata couponBurn
    ) external onlyCarbonLedger nonReentrant {
        _withdrawCarbonCredits(carbonCredit, tokenId, maturityId, amount, to, couponBurn);
    }

    /**
     * @dev Sets a new access manager for the vault
     * @param newAccessManager The address of the new access manager
     * @notice Only callable by an address with the appropriate permissions in the current access manager
     */
    function setAccessManager(address newAccessManager) external override onlySystemAdmin {
        if (newAccessManager == address(0)) revert Errors.ZeroAddressNotAllowed();

        // Update access manager in storage
        CarbonVaultStorage.getVaultConfigStorage().accessManager = newAccessManager;

        emit AccessManagerUpdated(newAccessManager);
    }

    /**
     * @dev Sets the maturity manager address
     * @param _maturityManager Address of the maturity manager contract
     */
    function setMaturityManager(address _maturityManager) external onlySystemAdmin {
        if (_maturityManager == address(0)) revert Errors.ZeroAddressNotAllowed();
        CarbonVaultStorage.getVaultConfigStorage().maturityManager = _maturityManager;
    }

    // ============== External View Functions ==============
    /**
     * @dev Get the total amount of carbon credits in the vault in tonnes (scaled by precision).
     *      This is the total amount of carbon credits in the vault, including reserved tonnes for coupons.
     * @return Total carbon credits in tonnes (scaled by precision).
     */
    function getTotalTonnes() external view override returns (uint256) {
        return CarbonVaultStorage.getVaultAccountingStorage().totalTonnes;
    }

    /**
     * @dev Get the balance of a specific carbon credit token.
     * For ERC20 tokens, tokenId is ignored and treated as 0.
     * For ERC1155 tokens, retrieves the balance of the specific tokenId.
     * @param carbonCredit Address of the carbon credit token
     * @param tokenId Token ID (used for ERC1155 tokens, ignored for ERC20)
     * @return Balance of the specified carbon credit
     */
    function balanceCarbonCredits(address carbonCredit, uint256 tokenId) external view override returns (uint256) {
        CarbonVaultStorage.VaultAccountingStorage storage vaultAccounting =
            CarbonVaultStorage.getVaultAccountingStorage();

        // Get token type from CarbonLedger
        CommonStructs.CreditConfig memory config = ICarbonLedger(carbonLedger()).getCreditDetails(carbonCredit);
        CommonStructs.TokenType tokenType = config.tokenType;

        // For ERC20 tokens, always use tokenId 0 regardless of what was passed
        if (tokenType == CommonStructs.TokenType.ERC20) {
            tokenId = 0;
        }

        return vaultAccounting.carbonCreditDeposits[carbonCredit][tokenId];
    }

    /**
     * @dev Get the configuration of a specific credit token
     * @param creditToken Address of the credit token
     * @return Configuration of the credit token
     */
    function getCarbonCreditConfig(address creditToken)
        external
        view
        override
        returns (CommonStructs.CreditConfig memory)
    {
        // Forward to CarbonLedger for single source of truth
        return ICarbonLedger(carbonLedger()).getCreditDetails(creditToken);
    }

    /**
     * @dev Get information about the vault
     * @return Name of the vault
     * @return Address of the access manager
     */
    function getClassVaultInfo() external view override returns (string memory, address) {
        return (name(), getAccessManager());
    }

    /**
     * @dev Get the total tonnes for a specific maturity ID
     * @param maturityId The maturity ID to query
     * @return Total tonnes for the specified maturity
     */
    function getMaturityTonnes(uint256 maturityId) external view override returns (uint256) {
        return CarbonVaultStorage.getMaturityAccountingStorage().maturityTonnes[maturityId];
    }

    /**
     * @dev Get tonnage amounts for multiple maturity IDs at once with struct return format
     * @param maturityIds Array of maturity IDs to query
     * @return maturityTonnes Array of MaturityTonnes structs with maturityId and tonnes paired together
     */
    function getMaturitiesTonnes(uint256[] calldata maturityIds)
        external
        view
        override
        returns (CommonStructs.MaturityTonnes[] memory maturityTonnes)
    {
        CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
            CarbonVaultStorage.getMaturityAccountingStorage();

        maturityTonnes = new CommonStructs.MaturityTonnes[](maturityIds.length);

        for (uint256 i = 0; i < maturityIds.length; i++) {
            maturityTonnes[i] = CommonStructs.MaturityTonnes({
                maturityId: maturityIds[i], tonnes: maturityAccounting.maturityTonnes[maturityIds[i]]
            });
        }

        return maturityTonnes;
    }

    /**
     * @dev Get the tonnes for a specific maturity, token address and token ID
     * @param maturityId The maturity ID to query
     * @param tokenAddress The token address to query
     * @param tokenId The token ID to query
     * @return Tonnes equivalent for the specified combination
     */
    function getTokenTonnesByMaturity(uint256 maturityId, address tokenAddress, uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        return CarbonVaultStorage.getMaturityAccountingStorage().maturityTokenTonnes[maturityId][tokenAddress][tokenId];
    }

    /**
     * @dev Get comprehensive tonnage information for the vault
     * @param maturityIds Array of maturity IDs to query
     * @return totalTonnes Total tonnes in the vault
     * @return liquidTonnes Liquid tonnes in the vault
     */
    function getSelectedVaultTonnes(uint256[] memory maturityIds)
        external
        view
        returns (uint256 totalTonnes, uint256 liquidTonnes)
    {
        return (
            CarbonVaultStorage.getVaultAccountingStorage().totalTonnes, // global_total
            CarbonVaultStorage.getMaturityAccountingStorage().liquidTonnes
        );
    }

    /**
     * @dev Get various vault tonnes metrics
     */
    function getVaultTonnes(uint256[] memory maturityIds)
        external
        view
        returns (
            uint256 totalTonnes,
            uint256 liquidTonnes,
            uint256 availableTonnes,
            CommonStructs.MaturityTonnes[] memory maturityTonnes
        )
    {
        return (
            CarbonVaultStorage.getVaultAccountingStorage().totalTonnes, // global_total
            CarbonVaultStorage.getMaturityAccountingStorage().liquidTonnes,
            this.getAvailableTonnes(), // this factors in reserved tonnes for coupons. a.k.a => AAM total
            this.getMaturitiesTonnes(maturityIds)
        );
    }

    /**
     * @dev Returns a list of tokenIds that are registered for this credit token.
     * @param creditToken The address of credit token.
     * @return An array of tokenIds that are registered for this credit token.
     */
    function getRegisteredTokenIds(address creditToken) external view returns (uint256[] memory) {
        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        // Return the stored array of tokenIds
        return tokenManagement.registeredCarbonCreditsMap[creditToken].tokenIds;
    }

    /**
     * @dev Returns the count of registered tokenIds for a credit token (O(1) storage read)
     * @param creditToken The address of the credit token
     * @return count Number of registered tokenIds
     */
    function getRegisteredTokenIdsCount(address creditToken) external view returns (uint256 count) {
        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        return tokenManagement.registeredCarbonCreditsMap[creditToken].tokenIds.length;
    }

    // ============== Public View Functions ==============
    /**
     * @dev Returns the current access manager address
     * @return address Access manager contract address
     */
    function getAccessManager() public view override returns (address) {
        return CarbonVaultStorage.getVaultConfigStorage().accessManager;
    }

    /**
     * @dev Converts tonnes to token amount using the conversion configuration
     * @param tonnes Amount of tonnes to convert
     * @param creditToken Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @return Amount of tokens equivalent to the specified tonnes
     */
    function convertTonnesToTokenAmount(uint256 tonnes, address creditToken, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        return _convertTonnesToTokenAmount(tonnes, creditToken, tokenId);
    }

    /**
     * @dev Converts token amount to tonnes using the conversion configuration
     * @param tokenAmount Amount of tokens to convert
     * @param creditToken Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @return Amount of tonnes equivalent to the specified tokens
     */
    function convertTokenAmountToTonnes(uint256 tokenAmount, address creditToken, uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return _convertTokenAmountToTonnes(tokenAmount, creditToken, tokenId);
    }

    /**
     * @dev Returns the name of the vault
     * @return The name of the vault
     */
    function name() public view override returns (string memory) {
        return CarbonVaultStorage.getVaultConfigStorage().name;
    }

    /**
     * @dev Gets the amount of tonnes available (not reserved for coupons)
     * @return The amount of available tonnes
     */
    function getAvailableTonnes() public view returns (uint256) {
        uint256 totalTonnes = CarbonVaultStorage.getVaultAccountingStorage().totalTonnes;
        uint256 reservedTonnes = CarbonVaultStorage.getCouponStorage().reservedTonnes;
        return totalTonnes >= reservedTonnes ? totalTonnes - reservedTonnes : 0;
    }

    /**
     * @dev Checks if there are enough available (unreserved) tonnes
     * @param tonnes The amount of tonnes to check
     * @return True if there are enough available tonnes
     */
    function hasEnoughAvailableTonnes(uint256 tonnes) public view returns (bool) {
        return tonnes <= getAvailableTonnes();
    }

    /**
     * @dev Get carbon ledger address
     * @return The address of the carbon ledger
     */
    function carbonLedger() public view returns (address) {
        return CarbonVaultStorage.getVaultConfigStorage().carbonLedger;
    }

    /**
     * @dev Get liquid tonnes amount
     */
    function getLiquidTonnes() public view returns (uint256) {
        return CarbonVaultStorage.getMaturityAccountingStorage().liquidTonnes;
    }

    /**
     * @dev Checks if a carbon credit is registered for a given token ID
     * @param creditToken The address of the credit token
     * @param tokenId The token ID to check
     * @return true if the carbon credit is registered, false otherwise
     */
    function isCarbonCreditRegistered(address creditToken, uint256 tokenId) public view returns (bool) {
        // Get token type from CarbonLedger
        CommonStructs.CreditConfig memory config = ICarbonLedger(carbonLedger()).getCreditDetails(creditToken);
        return ClassVaultRegistrationUtilsLib.isCarbonCreditRegistered(creditToken, tokenId, config.tokenType);
    }

    /**
     * @dev Returns the total amount of tonnes reserved for coupons
     * @return The amount of reserved tonnes
     */
    function getReservedTonnes() public view returns (uint256) {
        return CarbonVaultStorage.getCouponStorage().reservedTonnes;
    }

    /**
     * @dev Returns the balance of coupons for an account
     * @param account The account to get the balance for
     * @return The balance of coupons for the account
     */
    function getCouponBalance(address account) public view returns (uint256) {
        return _getCouponBalance(account);
    }

    /**
     * @dev Get liquid token tonnes for a specific token
     */
    function getLiquidTokenTonnes(address creditToken, uint256 tokenId) public view returns (uint256) {
        return CarbonVaultStorage.getMaturityAccountingStorage().liquidTokenTonnes[creditToken][tokenId];
    }

    /**
     * @dev Implementation of IERC1155Receiver for single token transfers
     * Always enforce security checks for production use
     */
    function onERC1155Received(
        address operator,
        address, /* from */
        uint256, /* id */
        uint256, /* value */
        bytes calldata
    )
        public
        view
        virtual
        override
        returns (bytes4)
    {
        // Allow transfers when operator is CarbonLedger (regardless of from address)
        // This allows direct transfers from users initiated by CarbonLedger
        if (operator != carbonLedger() && operator != address(this)) {
            revert Errors.TransferNotFromCarbonLedger();
        }

        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @dev Get the vault config
     * @return The vault config
     */
    function getVaultConfig() external pure returns (CarbonVaultStorage.VaultConfigStorage memory) {
        return CarbonVaultStorage.getVaultConfigStorage();
    }

    /**
     * @dev Implementation of IERC1155Receiver for batch token transfers
     * Always enforce security checks for production use
     */
    function onERC1155BatchReceived(
        address operator,
        address, /* from */
        uint256[] calldata, /* ids */
        uint256[] calldata, /* values */
        bytes calldata
    ) public view virtual override returns (bytes4) {
        // Allow transfers when operator is CarbonLedger (regardless of from address)
        // This allows direct transfers from users initiated by CarbonLedger
        if (operator != carbonLedger() && operator != address(this)) {
            revert Errors.TransferNotFromCarbonLedger();
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     * Properly implement ERC165 pattern to indicate support for IERC1155Receiver.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(ICarbonClassVault).interfaceId
            || interfaceId == type(ICarbonClassCoupons).interfaceId || super.supportsInterface(interfaceId);
    }

    // ============== Internal Functions ==============
    /**
     * @dev Function that authorizes an upgrade to a new implementation.
     * Required by the UUPSUpgradeable module.
     * Only accounts with the appropriate role can authorize upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlySystemAdmin {}

    /**
     * @dev Internal function for onlyCarbonLedger modifier
     */
    function _onlyCarbonLedger() internal view {
        if (msg.sender != carbonLedger()) revert Errors.NotCarbonLedger();
    }

    /**
     * @dev Internal function for onlySystemAdmin modifier
     */
    function _onlySystemAdmin() internal view {
        address accessManager = CarbonVaultStorage.getVaultConfigStorage().accessManager;
        (bool hasAdminRole,) =
            IAccessManager(accessManager).hasRole(CarbonSystemRoleLib.CARBON_SYSTEM_ADMIN, msg.sender);

        if (!hasAdminRole) revert Errors.NotSystemAdmin();
    }

    /**
     * @dev Internal function to convert tonnes to token amount
     * @param tonnes Amount of tonnes to convert
     * @param creditToken Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @return Amount of tokens equivalent to the specified tonnes
     */
    function _convertTonnesToTokenAmount(uint256 tonnes, address creditToken, uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        // Get token conversion config from CarbonLedger
        CommonStructs.CreditConfig memory config = ICarbonLedger(carbonLedger()).getCreditDetails(creditToken);

        // For ERC20 tokens, ensure tokenId is 0
        if (config.tokenType == CommonStructs.TokenType.ERC20 && tokenId != 0) {
            revert Errors.InvalidTokenId(tokenId);
        }

        // Use CarbonTonnageLib to convert tonnes to token amount
        return CarbonTonnageLib.tonnesToTokenAmount(tonnes, config.conversion);
    }

    function _convertTokenAmountToTonnes(uint256 tokenAmount, address creditToken, uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        // Get token conversion config from CarbonLedger
        CommonStructs.CreditConfig memory config = ICarbonLedger(carbonLedger()).getCreditDetails(creditToken);

        // For ERC20 tokens, ensure tokenId is 0
        if (config.tokenType == CommonStructs.TokenType.ERC20 && tokenId != 0) {
            revert Errors.InvalidTokenId(tokenId);
        }

        return CarbonTonnageLib.tokenAmountToTonnes(tokenAmount, config.conversion);
    }

    /**
     * @dev Internal logic for depositing carbon credits into the vault.
     *      Handles token transfers, state updates, and event emission.
     *      Assumes access control and reentrancy checks are done by the caller.
     * @param creditToken Address of the credit token
     * @param tokenId Token ID (for ERC1155 tokens)
     * @param maturityId ID of the maturity for tracking forward carbons
     * @param from Address to pull tokens from
     * @param amount Amount of tokens to deposit
     * @param couponBurn Parameters for burning coupons during deposit (optional)
     */
    function _depositCredits(
        address creditToken,
        uint256 tokenId,
        uint256 maturityId,
        address from,
        uint256 amount,
        ICarbonClassVault.CouponBurnParams memory couponBurn
    ) internal {
        CarbonVaultStorage.VaultConfigStorage storage vaultConfig = CarbonVaultStorage.getVaultConfigStorage();

        // Get credit info from CarbonLedger
        CommonStructs.CreditConfig memory creditConfig = ICarbonLedger(carbonLedger()).getCreditDetails(creditToken);

        // Check if credit+tokenId is registered with CarbonLedger
        if (!ClassVaultRegistrationUtilsLib.isCarbonCreditRegistered(creditToken, tokenId, creditConfig.tokenType)) {
            revert Errors.CreditNotRegistered();
        }

        // Determine if carbon is liquid directly if maturityId is 0
        bool isLiquid;
        if (maturityId == 0) {
            isLiquid = true; // MaturityId 0 indicates liquid carbon by convention
        } else {
            // Only verify maturity through MaturityManager if not using the special liquid carbon id
            address maturityManagerAddr = vaultConfig.maturityManager;
            if (maturityManagerAddr == address(0)) {
                revert Errors.MaturityManagerNotSet();
            }

            // // Get current maturity ID and active range
            // IMaturityManager.MaturityInfo memory maturityInfo =
            //     IMaturityManager(maturityManagerAddr).getMaturityInfo(maturityId);
            (uint256 start,) = IMaturityManager(maturityManagerAddr).getActiveMaturityRange();

            // Determine if carbon is liquid:
            // 1. If maturity is not active and is below the active range, it's liquid
            // 2. If maturity is in the active range, it's not liquid
            // 3. If maturity is above the active range, it's not liquid
            isLiquid = maturityId < start;
        }

        // Measure the balance delta so a delivery that differs from `amount` can be rejected below.
        // Credit tokens are external contracts, and callers (e.g. the AAM) have already priced `amount`.
        uint256 receivedAmount;

        // Handle token transfers based on token type
        if (creditConfig.tokenType == CommonStructs.TokenType.ERC1155) {
            // Verify approval for ERC1155
            if (!IERC1155(creditToken).isApprovedForAll(from, address(this))) {
                revert Errors.InsufficientApproval();
            }

            // Transfer tokens and measure the delta
            uint256 balanceBefore = IERC1155(creditToken).balanceOf(address(this), tokenId);
            IERC1155(creditToken).safeTransferFrom(from, address(this), tokenId, amount, "");
            receivedAmount = IERC1155(creditToken).balanceOf(address(this), tokenId) - balanceBefore;
        } else if (creditConfig.tokenType == CommonStructs.TokenType.ERC20) {
            // For ERC20 tokens
            if (IERC20(creditToken).allowance(from, address(this)) < amount) {
                revert Errors.InsufficientApproval();
            }

            // Ensure we're using tokenId 0 for ERC20
            tokenId = 0;

            // Transfer tokens and measure the delta
            uint256 balanceBefore = IERC20(creditToken).balanceOf(address(this));
            IERC20(creditToken).safeTransferFrom(from, address(this), amount);
            receivedAmount = IERC20(creditToken).balanceOf(address(this)) - balanceBefore;
        } else {
            revert Errors.InvalidTokenType();
        }

        if (receivedAmount == 0) revert Errors.AmountCannotBeZero();
        if (receivedAmount != amount) revert Errors.AmountMismatch(amount, receivedAmount);

        // receivedAmount == amount is enforced above, so this is the tonnage the caller priced.
        uint256 tonnesDeposited = CarbonTonnageLib.tokenAmountToTonnes(amount, creditConfig.conversion);

        // Check if we need to burn coupons
        if (couponBurn.tonnes > 0) {
            // Verify the coupon burn address is valid
            if (couponBurn.from == address(0)) revert Errors.ZeroAddressForCoupons();

            // Burn coupons from the specified address
            _burnCoupons(couponBurn.from, couponBurn.tonnes);
        }

        CarbonVaultStorage.VaultAccountingStorage storage vaultAccounting =
            CarbonVaultStorage.getVaultAccountingStorage();
        CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
            CarbonVaultStorage.getMaturityAccountingStorage();

        // Update deposits tracking (unified for both token types)
        vaultAccounting.carbonCreditDeposits[creditToken][tokenId] += amount;

        // Update total tonnes
        vaultAccounting.totalTonnes += tonnesDeposited;

        if (isLiquid) {
            // If liquid, track in liquid accounting (using tonnes)
            maturityAccounting.liquidTonnes += tonnesDeposited;
            maturityAccounting.liquidTokenTonnes[creditToken][tokenId] += tonnesDeposited;
        } else {
            // If forward carbon, track in maturity-specific accounting (using tonnes)
            maturityAccounting.maturityTokenTonnes[maturityId][creditToken][tokenId] += tonnesDeposited;
            maturityAccounting.maturityTonnes[maturityId] += tonnesDeposited;
        }
    }

    /**
     * @dev Internal implementation for withdrawing carbon credits
     * @param carbonCredit Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @param maturityId ID of the maturity to withdraw from (0 for liquid carbon)
     * @param amount Amount of tokens to withdraw
     * @param to Address to send the tokens to
     * @param couponBurn Parameters for burning coupons during withdrawal
     */
    function _withdrawCarbonCredits(
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to,
        ICarbonClassVault.CouponBurnParams memory couponBurn
    ) internal {
        // Get token conversion config from CarbonLedger
        CommonStructs.CreditConfig memory config = ICarbonLedger(carbonLedger()).getCreditDetails(carbonCredit);
        CommonStructs.TokenType tokenType = config.tokenType;

        // For ERC20 tokens, ensure tokenId is 0
        if (tokenType == CommonStructs.TokenType.ERC20) {
            tokenId = 0;
        }

        // Calculate tonnes equivalent being withdrawn
        uint256 tonnesWithdrawn = CarbonTonnageLib.tokenAmountToTonnes(amount, config.conversion);

        // Check if there are enough available (unreserved) tonnes
        if (!hasEnoughAvailableTonnes(tonnesWithdrawn)) {
            revert Errors.CannotWithdrawReservedTonnes();
        }

        CarbonVaultStorage.VaultAccountingStorage storage vaultAccounting =
            CarbonVaultStorage.getVaultAccountingStorage();

        // Check if vault has enough of the token
        uint256 balance = vaultAccounting.carbonCreditDeposits[carbonCredit][tokenId];
        if (balance < amount) {
            revert Errors.InsufficientTokenBalance();
        }

        CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
            CarbonVaultStorage.getMaturityAccountingStorage();

        // Handle different maturity buckets
        if (maturityId == 0) {
            // For liquid carbon (maturityId = 0)
            // Check if we have enough liquid tonnes in total
            if (maturityAccounting.liquidTonnes < tonnesWithdrawn) {
                revert Errors.InsufficientLiquidTonnes();
            }

            // Ensure withdrawal doesn't deplete coupon backing
            uint256 reservedTonnes = CarbonVaultStorage.getCouponStorage().reservedTonnes;

            uint256 burnTonnes = couponBurn.tonnes > 0 ? couponBurn.tonnes : 0;

            if (burnTonnes > 0 && burnTonnes > reservedTonnes) {
                revert Errors.CannotBurnMoreThanReserved();
            }

            if ((maturityAccounting.liquidTonnes - tonnesWithdrawn) < (reservedTonnes - burnTonnes)) {
                revert Errors.CannotWithdrawReservedTonnes();
            }

            // Check if we have enough liquid tonnes for this specific token
            if (maturityAccounting.liquidTokenTonnes[carbonCredit][tokenId] < tonnesWithdrawn) {
                revert Errors.InsufficientLiquidTokenTonnes();
            }

            // Update liquid accounting
            maturityAccounting.liquidTonnes -= tonnesWithdrawn;
            maturityAccounting.liquidTokenTonnes[carbonCredit][tokenId] -= tonnesWithdrawn;
        } else {
            // For specific maturity (maturityId > 0)
            // Check overall maturity tonnes
            if (maturityAccounting.maturityTonnes[maturityId] < tonnesWithdrawn) {
                revert Errors.InsufficientMaturityTonnes();
            }

            // Check token-specific maturity tonnes
            if (maturityAccounting.maturityTokenTonnes[maturityId][carbonCredit][tokenId] < tonnesWithdrawn) {
                revert Errors.InsufficientMaturityTokenTonnes();
            }

            // Update maturity accounting
            maturityAccounting.maturityTonnes[maturityId] -= tonnesWithdrawn;
            maturityAccounting.maturityTokenTonnes[maturityId][carbonCredit][tokenId] -= tonnesWithdrawn;
        }

        // Check if we need to burn coupons
        if (couponBurn.tonnes > 0) {
            // Verify the coupon burn address is valid
            if (couponBurn.from == address(0)) revert Errors.ZeroAddressForCoupons();

            // Burn coupons from the specified address
            _burnCoupons(couponBurn.from, couponBurn.tonnes);
        }

        // Update vault accounting
        vaultAccounting.carbonCreditDeposits[carbonCredit][tokenId] = balance - amount;
        vaultAccounting.totalTonnes -= tonnesWithdrawn;

        // Transfer tokens based on type
        if (tokenType == CommonStructs.TokenType.ERC1155) {
            IERC1155(carbonCredit).safeTransferFrom(address(this), to, tokenId, amount, "");
        } else if (tokenType == CommonStructs.TokenType.ERC20) {
            IERC20(carbonCredit).safeTransfer(to, amount);
        } else {
            revert Errors.InvalidTokenType();
        }
    }

    /**
     * @dev Upgrades the implementation of the proxy to a new address.
     * Required by the UUPSUpgradeable pattern.
     * @param newImplementation Address of the new implementation contract
     */
    function upgradeTo(address newImplementation) public override onlySystemAdmin {
        upgradeToAndCall(newImplementation, new bytes(0));
    }

    function matureForwardCarbon(uint256 maturityId) external nonReentrant onlyCarbonLedger {
        CarbonVaultStorage.VaultConfigStorage storage vaultConfig = CarbonVaultStorage.getVaultConfigStorage();
        CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
            CarbonVaultStorage.getMaturityAccountingStorage();
        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        // Get maturity timestamp
        address maturityManagerAddr = vaultConfig.maturityManager;
        if (maturityManagerAddr == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        uint256 maturityTimestamp = IMaturityManager(maturityManagerAddr).getMaturityTimestamp(maturityId);

        // Only mature if maturityTimestamp has been reached
        if (block.timestamp < maturityTimestamp) {
            revert Errors.MaturityNotReached(maturityId, maturityTimestamp);
        }

        // Get tonnes for this maturity
        uint256 maturityTonnes = maturityAccounting.maturityTonnes[maturityId];

        // Check if already matured (no liquid tonnes to add)
        if (maturityTonnes == 0) {
            revert Errors.NoTonnesToMature();
        }

        // Transfer aggregate tonnes from maturity to liquid accounting
        maturityAccounting.liquidTonnes += maturityTonnes;
        // Clear maturity tonnes after transferring to liquid
        maturityAccounting.maturityTonnes[maturityId] = 0;

        // Process all ERC20 token credits
        for (uint256 i = 0; i < tokenManagement.registeredERC20CarbonCredits.length; i++) {
            address tokenAddr = tokenManagement.registeredERC20CarbonCredits[i];
            uint256 tokenId = 0; // ERC20 always uses tokenId 0

            uint256 tokenMaturityTonnes = maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId];
            if (tokenMaturityTonnes > 0) {
                // Transfer tonnes from maturity accounting to liquid accounting
                maturityAccounting.liquidTokenTonnes[tokenAddr][tokenId] += tokenMaturityTonnes;
                // Clear maturity-specific token tonnes after transferring to liquid
                maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId] = 0;
            }
        }

        // Process all ERC1155 token credits
        for (uint256 i = 0; i < tokenManagement.registeredERC1155CarbonCredits.length; i++) {
            address tokenAddr = tokenManagement.registeredERC1155CarbonCredits[i];
            uint256[] memory tokenIds = tokenManagement.registeredCarbonCreditsMap[tokenAddr].tokenIds;

            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];
                uint256 tokenMaturityTonnes = maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId];

                if (tokenMaturityTonnes > 0) {
                    // Transfer tonnes from maturity accounting to liquid accounting
                    maturityAccounting.liquidTokenTonnes[tokenAddr][tokenId] += tokenMaturityTonnes;
                    // Clear maturity-specific token tonnes after transferring to liquid
                    maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId] = 0;
                }
            }
        }

        emit ForwardCarbonMatured(maturityId, maturityTonnes);
    }

    /**
     * @notice Matures forward carbon for a specific maturity ID in batches
     * @dev Allows processing a subset of tokens per transaction to avoid gas limits
     * @param maturityId The maturity ID to mature forward carbon for
     * @param erc20Tokens Array of ERC20 token addresses to process
     * @param erc1155Tokens Array of ERC1155 token addresses to process
     * @param erc1155TokenIds Array of token ID arrays corresponding to each ERC1155 token
     */
    function matureForwardCarbonBatch(
        uint256 maturityId,
        address[] calldata erc20Tokens,
        address[] calldata erc1155Tokens,
        uint256[][] calldata erc1155TokenIds
    ) external nonReentrant onlyCarbonLedger {
        // Validate array lengths match
        if (erc1155Tokens.length != erc1155TokenIds.length) {
            revert Errors.InvalidArrayLength();
        }

        CarbonVaultStorage.VaultConfigStorage storage vaultConfig = CarbonVaultStorage.getVaultConfigStorage();
        CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
            CarbonVaultStorage.getMaturityAccountingStorage();

        // Get maturity timestamp
        address maturityManagerAddr = vaultConfig.maturityManager;
        if (maturityManagerAddr == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        uint256 maturityTimestamp = IMaturityManager(maturityManagerAddr).getMaturityTimestamp(maturityId);

        // Only mature if maturityTimestamp has been reached
        if (block.timestamp < maturityTimestamp) {
            revert Errors.MaturityNotReached(maturityId, maturityTimestamp);
        }

        // Calculate total batch size for validation
        uint256 totalItems = erc20Tokens.length;
        for (uint256 i = 0; i < erc1155TokenIds.length; i++) {
            totalItems += erc1155TokenIds[i].length;
        }

        // Validate batch size if configured
        uint256 maxBatch = vaultConfig.maxBatchSize;
        if (maxBatch > 0 && totalItems > maxBatch) {
            revert Errors.BatchSizeTooLarge(totalItems, maxBatch);
        }

        // Track total tonnes moved in this batch
        uint256 totalTonnesMoved = 0;

        // Process specified ERC20 tokens
        for (uint256 i = 0; i < erc20Tokens.length; i++) {
            address tokenAddr = erc20Tokens[i];
            uint256 tokenId = 0; // ERC20 always uses tokenId 0

            // Verify token is registered before processing
            if (!ClassVaultRegistrationUtilsLib.isCarbonCreditRegistered(
                    tokenAddr, tokenId, CommonStructs.TokenType.ERC20
                )) {
                revert Errors.CreditNotRegistered();
            }

            uint256 tokenMaturityTonnes = maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId];
            if (tokenMaturityTonnes > 0) {
                // Transfer tonnes from maturity accounting to liquid accounting
                maturityAccounting.liquidTokenTonnes[tokenAddr][tokenId] += tokenMaturityTonnes;
                // Clear maturity-specific token tonnes
                maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId] = 0;
                totalTonnesMoved += tokenMaturityTonnes;
            }
        }

        // Process specified ERC1155 tokens
        for (uint256 i = 0; i < erc1155Tokens.length; i++) {
            address tokenAddr = erc1155Tokens[i];
            uint256[] calldata tokenIds = erc1155TokenIds[i];

            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];

                // Verify token is registered before processing
                if (!ClassVaultRegistrationUtilsLib.isCarbonCreditRegistered(
                        tokenAddr, tokenId, CommonStructs.TokenType.ERC1155
                    )) {
                    revert Errors.CreditNotRegistered();
                }

                uint256 tokenMaturityTonnes = maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId];

                if (tokenMaturityTonnes > 0) {
                    // Transfer tonnes from maturity accounting to liquid accounting
                    maturityAccounting.liquidTokenTonnes[tokenAddr][tokenId] += tokenMaturityTonnes;
                    // Clear maturity-specific token tonnes
                    maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId] = 0;
                    totalTonnesMoved += tokenMaturityTonnes;
                }
            }
        }

        // Revert if no tonnes were moved in this batch
        if (totalTonnesMoved == 0) {
            revert Errors.NoTonnesToMature();
        }

        // Defensive check to prevent underflow
        if (maturityAccounting.maturityTonnes[maturityId] < totalTonnesMoved) {
            revert Errors.InsufficientMaturityTonnes();
        }

        // Update aggregate accounting
        maturityAccounting.liquidTonnes += totalTonnesMoved;
        maturityAccounting.maturityTonnes[maturityId] -= totalTonnesMoved;

        emit ForwardCarbonMatured(maturityId, totalTonnesMoved);
    }

    /**
     * @notice Sets the maximum batch size for batch operations
     * @param _maxBatchSize Maximum number of tokens allowed per batch (0 = unlimited)
     */
    function setMaxBatchSize(uint256 _maxBatchSize) external onlySystemAdmin {
        CarbonVaultStorage.getVaultConfigStorage().maxBatchSize = _maxBatchSize;
    }

    /**
     * @notice Updates the maturity ID for a set of credit tokens, transferring any existing tonnes
     * @param creditToken The address of the credit token
     * @param tokenIds Array of token IDs to update
     * @param oldMaturityId The current maturity ID to transfer from
     * @param newMaturityId The new maturity ID to transfer to
     */
    function updateMaturityId(
        address creditToken,
        uint256[] memory tokenIds,
        uint256 oldMaturityId,
        uint256 newMaturityId
    ) external onlySystemAdmin {
        CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
            CarbonVaultStorage.getMaturityAccountingStorage();
        CarbonVaultStorage.VaultConfigStorage storage vaultConfig = CarbonVaultStorage.getVaultConfigStorage();

        // Prevent no-op when both IDs are the same
        if (oldMaturityId == newMaturityId) {
            revert Errors.SameMaturityId();
        }

        // Validate batch size if configured
        uint256 maxBatch = vaultConfig.maxBatchSize;
        if (maxBatch > 0 && tokenIds.length > maxBatch) {
            revert Errors.BatchSizeTooLarge(tokenIds.length, maxBatch);
        }

        // Verify maturity manager is set
        address maturityManagerAddr = vaultConfig.maturityManager;
        if (maturityManagerAddr == address(0)) {
            revert Errors.MaturityManagerNotSet();
        }

        // Only validate non-zero maturity IDs through MaturityManager
        // MaturityId 0 is the liquid carbon convention and doesn't need validation
        if (newMaturityId != 0) {
            IMaturityManager.MaturityInfo memory maturityInfo =
                IMaturityManager(maturityManagerAddr).getMaturityInfo(newMaturityId);

            if (!maturityInfo.exists) {
                revert Errors.InvalidMaturityId(newMaturityId);
            }

            // Verify new maturity is active
            if (!maturityInfo.isActive) {
                revert Errors.InvalidMaturityId(newMaturityId);
            }
        }

        // Track total tonnes moved
        uint256 totalTonnesMoved = 0;

        // For each token ID
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Get current tonnes from appropriate storage
            uint256 currentTonnes;
            if (oldMaturityId == 0) {
                currentTonnes = maturityAccounting.liquidTokenTonnes[creditToken][tokenId];
            } else {
                currentTonnes = maturityAccounting.maturityTokenTonnes[oldMaturityId][creditToken][tokenId];
            }

            // Only update if there are existing tonnes
            if (currentTonnes > 0) {
                // Verify this token is registered before migrating tonnes
                if (!isCarbonCreditRegistered(creditToken, tokenId)) {
                    revert Errors.CreditNotRegistered();
                }
                // Remove tonnes from old location
                if (oldMaturityId == 0) {
                    // Ensure migration doesn't deplete coupon backing
                    uint256 reservedTonnes = CarbonVaultStorage.getCouponStorage().reservedTonnes;
                    if (maturityAccounting.liquidTonnes - currentTonnes < reservedTonnes) {
                        revert Errors.CannotWithdrawReservedTonnes();
                    }
                    maturityAccounting.liquidTokenTonnes[creditToken][tokenId] = 0;
                    maturityAccounting.liquidTonnes -= currentTonnes;
                } else {
                    maturityAccounting.maturityTokenTonnes[oldMaturityId][creditToken][tokenId] = 0;
                    maturityAccounting.maturityTonnes[oldMaturityId] -= currentTonnes;
                }

                // Add tonnes to new location
                if (newMaturityId == 0) {
                    maturityAccounting.liquidTokenTonnes[creditToken][tokenId] += currentTonnes;
                    maturityAccounting.liquidTonnes += currentTonnes;
                } else {
                    maturityAccounting.maturityTokenTonnes[newMaturityId][creditToken][tokenId] += currentTonnes;
                    maturityAccounting.maturityTonnes[newMaturityId] += currentTonnes;
                }

                // Accumulate total tonnes moved
                totalTonnesMoved += currentTonnes;
            }
        }

        // Revert if no tonnes were actually moved
        if (totalTonnesMoved == 0) {
            revert Errors.NoTonnesToMigrate();
        }

        // Emit event with migration details
        emit MaturityIdMigrated(creditToken, oldMaturityId, newMaturityId, tokenIds, totalTonnesMoved);
    }
}

