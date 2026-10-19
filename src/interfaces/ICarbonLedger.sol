// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ICarbonClassVault.sol";
import "../libraries/CommonStructs.sol";
import "../interfaces/ICommonEvents.sol";

interface ICarbonLedger is ICommonEvents {
    // Enums
    enum TokenType {
        ERC20,
        ERC1155
    }

    // Events
    event ClassVaultRegistered(address indexed classVault);
    event ClassVaultUnregistered(address indexed classVault);
    event CreditRegisteredForClass(address indexed classVault, address indexed creditToken, uint256[] tokenIds);
    event CreditUnregisteredForClass(address indexed classVault, address indexed creditToken, uint256[] tokenIds);
    event TokenIdRegisteredForClass(address indexed classVault, address indexed creditToken, uint256 indexed tokenId);
    event TokenIdUnregisteredForClass(address indexed classVault, address indexed creditToken, uint256 indexed tokenId);

    event CreditLiquidityAddedToClassVault(
        address indexed classVault, address indexed creditToken, address indexed from, uint256 amount, uint256 tokenId
    );
    event CreditLiquidityRemovedFromClassVault(
        address indexed classVault, address indexed creditToken, address indexed to, uint256 amount, uint256 tokenId
    );
    event EmergencyLiquidityRemoved(
        address indexed classVault,
        address indexed creditToken,
        address indexed to,
        uint256 amount,
        uint256 tokenId,
        uint256 maturityId
    );
    event CreditsMigratedBetweenClasses(
        address indexed sourceVault, address indexed targetVault, address creditToken, uint256 amount, uint256 tokenId
    );
    event CreditConfigSet(
        address indexed carbonCredit, CommonStructs.TokenType tokenType, CommonStructs.ConversionConfig conversionConfig
    );
    event MaxTokenIdsPerMigrationUpdated(uint256 oldMax, uint256 newMax);
    event MaxTokenIdsPerUnregisterUpdated(uint256 oldMax, uint256 newMax);

    // Class management functions
    function registerClass(address classVault) external;
    function unregisterClass(address classVault) external;

    // Credit registry functions
    function registerCreditForClass(address carbonClass, address carbonCredit, uint256[] calldata tokenIds) external;
    function unregisterCreditForClass(address carbonClass, address carbonCredit, uint256[] calldata tokenIds) external;

    /**
     * @dev Adds information about a new credit token recognized by the ledger.
     * @param tokenType The type of the token (ERC20 or ERC1155).
     * @param carbonCredit The address of the credit token.
     * @param conversionConfig Configuration for unit conversion.
     */
    function addCreditConfig(
        address carbonCredit,
        CommonStructs.TokenType tokenType,
        CommonStructs.ConversionConfig memory conversionConfig
    ) external;

    /**
     * @dev Updates information for an existing credit token.
     * @param tokenType The type of the token (ERC20 or ERC1155).
     * @param carbonCredit The address of the credit token.
     * @param conversionConfig Configuration for unit conversion.
     */
    function updateCreditConfig(
        address carbonCredit,
        CommonStructs.TokenType tokenType,
        CommonStructs.ConversionConfig memory conversionConfig
    ) external;

    // Liquidity management functions
    /**
     * @dev Adds credit token liquidity to a class vault from a specified address. Requires caller to have CARBON_LIQUIDITY_MANAGER_ROLE or ADMIN_ROLE.
     * @param carbonClass The address of the class vault.
     * @param carbonCredit The address of the credit token.
     * @param tokenId The ID of the token (for ERC1155, 0 for ERC20).
     * @param maturityId ID of the maturity for tracking forward carbons
     * @param from The address providing the liquidity.
     * @param amount The amount of tokens to add.
     * @param couponBurn Parameters for burning coupons during deposit (optional)
     */
    function addCreditLiquidityToClassVault(
        address carbonClass,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        address from,
        uint256 amount,
        ICarbonClassVault.CouponBurnParams calldata couponBurn
    ) external;

    /**
     * @dev Removes credit token liquidity from a class vault and sends it to a specified address. Requires caller to have CARBON_LIQUIDITY_MANAGER_ROLE or ADMIN_ROLE.
     * @param carbonClass The address of the class vault.
     * @param carbonCredit The address of the credit token.
     * @param tokenId The ID of the token (for ERC1155, 0 for ERC20).
     * @param maturityId ID of the maturity for tracking forward carbons
     * @param amount The amount of tokens to remove.
     * @param to The address to receive the removed tokens.
     * @param couponBurn Parameters for burning coupons during withdrawal (optional)
     */
    function removeCreditLiquidityFromClassVault(
        address carbonClass,
        address carbonCredit,
        uint256 tokenId,
        uint256 maturityId,
        uint256 amount,
        address to,
        ICarbonClassVault.CouponBurnParams calldata couponBurn
    ) external;

    /**
     * @dev [Admin Only] Emergency function to remove liquidity bypassing registration checks.
     *      Use when class or credit is unregistered but funds need to be recovered.
     * @param classVault The address of the class vault.
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
    ) external;

    // Helper functions
    /**
     * @dev Retrieves the detailed information for a specific credit token.
     * @param carbonCredit The address of the credit token.
     * @return CreditConfig memory structure containing details about the token.
     */
    function getCreditDetails(address carbonCredit) external view returns (CommonStructs.CreditConfig memory);

    /**
     * @dev Migrates credit tokens between two registered class vaults. Requires caller to have ADMIN_ROLE or MANAGER_ROLE.
     * For ERC20 tokens, pass a single-element array with tokenIds[0] = 0 and amounts[0] = amount.
     * For ERC1155 tokens, you MUST provide specific tokenIds and amounts to migrate.
     * @param sourceCarbonClass The source class vault address.
     * @param targetCarbonClass The target class vault address.
     * @param carbonCredit The address of the credit token to migrate.
     * @param tokenIds For ERC20: [0]. For ERC1155: array of token IDs to migrate (required).
     * @param amounts The amounts of tokens to migrate for each tokenId.
     */
    function migrateCreditBetweenClasses(
        address sourceCarbonClass,
        address targetCarbonClass,
        address carbonCredit,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external;

    /**
     * @dev Removes dust from the carbon ledger
     * @param tokenAddress The address of the token to remove dust from.
     * @param to The address to send the dust to.
     */
    function removeDust(address tokenAddress, address to) external;

    // View functions
    /**
     * @dev Checks if a class vault is currently whitelisted (registered) in the ledger.
     * @param carbonClass The address of the class vault.
     * @return bool True if the class vault is registered, false otherwise.
     */
    function isClassRegistered(address carbonClass, bool shouldRevert) external view returns (bool);

    /**
     * @dev Checks if a specific credit token is whitelisted (registered) for a given class vault.
     * @param carbonClass The address of the class vault.
     * @param carbonCredit The address of the credit token.
     * @return bool True if the credit token is registered for the class vault, false otherwise.
     */
    function isCreditRegisteredForClass(address carbonClass, address carbonCredit, bool shouldRevert)
        external
        view
        returns (bool);

    /**
     * @dev Returns the current access manager address
     * @return address Access manager contract address
     */
    function getAccessManager() external view returns (address);

    /**
     * @dev Sets a new access manager for the ledger
     * @param newAccessManager The address of the new access manager
     */
    function setAccessManager(address newAccessManager) external;

    /**
     * @dev Returns the maximum number of tokenIds allowed per migration
     * @return uint256 Maximum number of tokenIds
     */
    function getMaxTokenIdsPerMigration() external view returns (uint256);

    /**
     * @dev Sets the maximum number of tokenIds allowed per migration
     * @param newMax The new maximum number of tokenIds
     */
    function setMaxTokenIdsPerMigration(uint256 newMax) external;

    /**
     * @dev Pauses the carbon ledger
     */
    function pauseCarbonLedger() external;

    /**
     * @dev Unpauses the carbon ledger
     */
    function unpauseCarbonLedger() external;

    /**
     * @dev Checks if the carbon ledger is paused
     * @return bool True if the carbon ledger is paused, false otherwise
     */
    function isSystemPaused() external view returns (bool);

    /**
     * @dev Executes maturity for forward carbon in a class vault
     * @param classVault The address of the class vault
     * @param maturityId The maturity ID to mature
     */
    function executeMatureForwardCarbon(address classVault, uint256 maturityId) external;

    /**
     * @dev Executes maturity for forward carbon in a class vault with batch processing
     * @param classVault The address of the class vault
     * @param maturityId The maturity ID to mature
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
    ) external;
}
