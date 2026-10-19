// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICommonEvents} from "../interfaces/ICommonEvents.sol";
import {CommonStructs} from "../libraries/CommonStructs.sol";

interface ICarbonClassVault is ICommonEvents {
    // ============== Structs ==============
    /**
     * @dev Struct for initialization parameters
     */
    struct VaultConfigInitParams {
        address carbonLedger;
        address accessManager;
        address maturityManager;
        address registrationManager;
        string name;
        string symbol;
    }

    /**
     * @dev Parameters for burning coupons during operations
     */
    struct CouponBurnParams {
        uint256 tonnes;
        address from;
    }

    struct AssetConfig {
        CommonStructs.TokenType tokenType;
        CommonStructs.ConversionConfig conversion;
        uint256 totalDeposited;
    }

    // ============== Events ==============

    /**
     * @dev Emitted when total tonnes are synchronized
     */
    event TotalTonnesSynced(uint256 newTotalTonnes);

    /**
     * @dev Emitted when token tonnes are rebalanced
     */
    event TokenTonnesRebalanced(
        address[] creditTokens, uint256[] tokenIds, uint256 oldTotalTonnes, uint256 newTotalTonnes
    );

    /**
     * @dev Emitted when forward carbon credits reach their maturity date and become liquid
     */
    event ForwardCarbonMatured(uint256 indexed maturityId, uint256 tonnes);

    /**
     * @dev Emitted when maturity IDs are updated for carbon credits
     */
    event MaturityUpdated(address indexed creditToken, uint256[] tokenIds, uint256 maturityId, bool isLiquid);

    /**
     * @dev Emitted when carbon credits are migrated from one maturity ID to another
     */
    event MaturityIdMigrated(
        address indexed creditToken,
        uint256 indexed oldMaturityId,
        uint256 indexed newMaturityId,
        uint256[] tokenIds,
        uint256 totalTonnesMoved
    );

    /**
     * @dev Emitted when the registration manager is updated
     */
    event RegistrationManagerUpdated(address indexed registrationManager);

    // ============== Credit Management Functions ==============

    /**
     * @dev Register a carbon credit token for use with this vault
     * @param creditToken Address of the carbon credit token to register
     * @param tokenIds Array of token IDs to register (for ERC1155 tokens, empty or [0] for ERC20)
     * @param CreditConfig Credit information structure
     * @return Success flag
     */
    function registerCarbonCredit(
        address creditToken,
        uint256[] memory tokenIds,
        CommonStructs.CreditConfig calldata CreditConfig
    ) external returns (bool);

    /**
     * @dev Unregister a carbon credit tokenId from this vault
     * @param creditToken Address of the credit token to unregister
     * @param tokenId The token ID to unregister
     */
    function unregisterCarbonCredit(address creditToken, uint256 tokenId) external;

    // ============== Liquidity Management Functions ==============

    /**
     * @dev Deposit carbon credits into the vault
     * @param creditToken Address of the credit token
     * @param tokenId Token ID (for ERC1155 tokens... for ERC20 tokens, this is 0)
     * @param maturityId ID of the maturity for tracking forward carbons
     * @param from Address to pull tokens from
     * @param amount Amount of tokens to deposit
     * @param couponBurn Parameters for burning coupons during deposit
     */
    function depositCarbonCredits(
        address creditToken,
        uint256 tokenId,
        uint256 maturityId,
        address from,
        uint256 amount,
        CouponBurnParams calldata couponBurn
    ) external;

    /**
     * @dev Withdraw carbon credits from the vault
     * @param creditToken Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @param maturityId ID of the maturity to withdraw from (0 for liquid carbon)
     * @param amount Amount of tokens to withdraw
     * @param to Address to send the tokens to
     * @param couponBurn Parameters for burning coupons during withdrawal
     */
    function withdrawCarbonCredits(
        address creditToken,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to,
        CouponBurnParams calldata couponBurn
    ) external;

    /**
     * @dev Matures forward carbon for a specific maturity ID
     * @param maturityId The maturity ID to mature forward carbon for
     */
    function matureForwardCarbon(uint256 maturityId) external;

    /**
     * @dev Matures forward carbon for a specific maturity ID in batches
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
    ) external;

    // ============== View Functions - General ==============

    /**
     * @dev Get information about the vault
     * @return Name of the vault and address of the access manager
     */
    function getClassVaultInfo() external view returns (string memory, address);

    // ============== View Functions - Tonne Management ==============

    /**
     * @dev Get the total amount of carbon credits in the vault in tonnes (scaled by precision)
     * @return Total carbon credits in tonnes
     */
    function getTotalTonnes() external view returns (uint256);

    /**
     * @dev Gets the amount of tonnes available (not reserved for coupons)
     * @return The amount of available tonnes
     */
    function getAvailableTonnes() external view returns (uint256);

    /**
     * @dev Returns the total amount of tonnes reserved for coupons
     * @return The amount of reserved tonnes
     */
    function getReservedTonnes() external view returns (uint256);

    /**
     * @dev Get liquid tonnes amount
     * @return The amount of liquid tonnes
     */
    function getLiquidTonnes() external view returns (uint256);

    /**
     * @dev Get the total tonnes for a specific maturity ID
     * @param maturityId The maturity ID to query
     * @return Total tonnes for the specified maturity
     */
    function getMaturityTonnes(uint256 maturityId) external view returns (uint256);

    /**
     * @dev Get tonnage amounts for multiple maturity IDs at once with struct return format
     * @param maturityIds Array of maturity IDs to query
     * @return maturityTonnes Array of MaturityTonnes structs with maturityId and tonnes paired together
     */
    function getMaturitiesTonnes(uint256[] calldata maturityIds)
        external
        view
        returns (CommonStructs.MaturityTonnes[] memory maturityTonnes);

    /**
     * @dev Get comprehensive tonnage information for the vault
     * @param maturityIds Array of maturity IDs to query
     * @return totalTonnes Total tonnes in the vault
     * @return liquidTonnes Liquid tonnes in the vault
     */
    function getSelectedVaultTonnes(uint256[] memory maturityIds)
        external
        view
        returns (uint256 totalTonnes, uint256 liquidTonnes);

    /**
     * @dev Get comprehensive tonnage information for the vault
     * @param maturityIds Array of maturity IDs to query
     * @return totalTonnes Total tonnes in the vault
     * @return liquidTonnes Liquid tonnes in the vault
     * @return availableTonnes Available tonnes (not reserved for coupons)
     * @return maturityTonnes Array of MaturityTonnes structs with maturity-specific information
     */
    function getVaultTonnes(uint256[] memory maturityIds)
        external
        view
        returns (
            uint256 totalTonnes,
            uint256 liquidTonnes,
            uint256 availableTonnes,
            CommonStructs.MaturityTonnes[] memory maturityTonnes
        );

    // ============== View Functions - Token Management ==============

    /**
     * @dev Get the balance of a specific carbon credit token
     * @param carbonCredit Address of the carbon credit token
     * @param tokenId Token ID (used for ERC1155 tokens, ignored for ERC20)
     * @return Balance of the specified carbon credit
     */
    function balanceCarbonCredits(address carbonCredit, uint256 tokenId) external view returns (uint256);

    /**
     * @dev Get the configuration of a specific credit token
     * @param creditToken Address of the credit token
     * @return Configuration of the credit token
     */
    function getCarbonCreditConfig(address creditToken) external view returns (CommonStructs.CreditConfig memory);

    /**
     * @dev Get liquid token tonnes for a specific token
     * @param creditToken Address of the credit token
     * @param tokenId The token ID to query
     * @return The amount of liquid tonnes for the specified token
     */
    function getLiquidTokenTonnes(address creditToken, uint256 tokenId) external view returns (uint256);

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
        returns (uint256);

    /**
     * @dev Returns the list of registered tokenIds for a specific ERC1155 credit token
     * @param creditToken The address of the ERC1155 credit token
     * @return An array of registered token IDs for the given credit token
     */
    function getRegisteredTokenIds(address creditToken) external view returns (uint256[] memory);

    /**
     * @dev Returns the count of registered tokenIds for a credit token (O(1) storage read)
     * @param creditToken The address of the credit token
     * @return count Number of registered tokenIds
     */
    function getRegisteredTokenIdsCount(address creditToken) external view returns (uint256 count);

    /**
     * @dev Returns true if the carbon credit is registered in the vault
     * @param creditToken The address of the credit token to check
     * @param tokenId The ID of the token to check
     * @return true if the carbon credit is registered, false otherwise
     */
    function isCarbonCreditRegistered(address creditToken, uint256 tokenId) external view returns (bool);

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
        returns (uint256);

    /**
     * @dev Converts tonnes to a token amount using the conversion configuration
     * @param tonnes Carbon tonnes (18-dec standardized) to convert
     * @param creditToken Address of the carbon credit token
     * @param tokenId Token ID (for ERC1155 tokens, 0 for ERC20)
     * @return Equivalent token amount in the credit's native decimal representation
     */
    function convertTonnesToTokenAmount(uint256 tonnes, address creditToken, uint256 tokenId)
        external
        view
        returns (uint256);

    // ============== View Functions - Coupon Management ==============

    /**
     * @dev Returns the balance of coupons for an account
     * @param account The account to get the balance for
     * @return The balance of coupons for the account
     */
    function getCouponBalance(address account) external view returns (uint256);

    // ============== Access Management Functions ==============

    /**
     * @dev Returns the address of the AccessManager contract
     * @return The address of the current access manager
     */
    function getAccessManager() external view returns (address);

    /**
     * @dev Sets a new access manager
     * @param newAccessManager The address of the new access manager
     */
    function setAccessManager(address newAccessManager) external;

    /**
     * @dev Sets a new maturity manager
     * @param newMaturityManager The address of the new maturity manager
     */
    function setMaturityManager(address newMaturityManager) external;

    /**
     * @dev Sets the maximum batch size for batch operations
     * @param _maxBatchSize Maximum number of tokens allowed per batch (0 = unlimited)
     */
    function setMaxBatchSize(uint256 _maxBatchSize) external;

    /**
     * @dev Updates the maturity ID for specific carbon credit token IDs
     * @param creditToken Address of the carbon credit token
     * @param tokenIds Array of token IDs to update
     * @param oldMaturityId The current maturity ID
     * @param newMaturityId The new maturity ID to assign
     */
    function updateMaturityId(
        address creditToken,
        uint256[] memory tokenIds,
        uint256 oldMaturityId,
        uint256 newMaturityId
    ) external;

    /**
     * @dev Upgrades the implementation of the proxy to a new address.
     * Required by the UUPSUpgradeable pattern.
     * @param newImplementation Address of the new implementation contract
     */
    function upgradeTo(address newImplementation) external;

    /**
     * @dev Initializes the contract for use with a proxy
     * @param vaultParams Struct containing vault configuration parameters
     */
    function initialize(VaultConfigInitParams memory vaultParams) external;
}
