// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../libraries/CarbonVaultStorage.sol";

import "../libraries/Errors.sol";
import "../libraries/ClassVaultRegistrationUtilsLib.sol";
import "../libraries/CommonStructs.sol";
import "../interfaces/ICarbonLedger.sol";
import "../interfaces/ICarbonClassVault.sol";

/**
 * @title ClassVaultRegistrationManager
 * @dev Contract for managing carbon credit token registration in CarbonClassVault
 * Designed to be used ONLY via delegatecall from CarbonClassVault
 */
contract ClassVaultRegistrationManager {
    /**
     * @dev Check if this call is via delegatecall from a vault
     * When called via delegatecall, this will check CarbonVaultStorage which
     * is stored in the vault's storage context, not this contract's
     */
    function _requireDelegateCall() private view {
        // In a delegatecall context, msg.sender is preserved but address(this) is the caller's address
        // So this check verifies we're being delegate-called from a vault with its own storage
        address storedLedger = CarbonVaultStorage.getVaultConfigStorage().carbonLedger;
        if (storedLedger == address(0)) {
            revert Errors.NotAuthorized();
        }
    }

    /**
     * @dev Register a carbon credit token for use with a vault
     * @param creditToken Address of the carbon credit token to register
     * @param tokenIds Array of token IDs to register (for ERC1155 tokens, empty or [0] for ERC20)
     * @param creditConfig Credit info from the CarbonLedger
     * @return success True if registration was successful, false otherwise
     */
    function registerCarbonCredit(
        address creditToken,
        uint256[] calldata tokenIds,
        CommonStructs.CreditConfig memory creditConfig
    ) external returns (bool success) {
        _requireDelegateCall();

        if (creditToken == address(0)) revert Errors.ZeroAddressNotAllowed();

        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        // Check if token is already configured in this vault
        CommonStructs.TokenType tokenType = creditConfig.tokenType;
        CarbonVaultStorage.RegisteredTokenConfig storage tokenConfig =
            tokenManagement.registeredCarbonCreditsMap[creditToken];

        // Determine if this is first registration by checking if token is in registered arrays
        bool isFirstRegistration = false;
        if (tokenType == CommonStructs.TokenType.ERC20) {
            isFirstRegistration = tokenConfig.index >= tokenManagement.registeredERC20CarbonCredits.length
                || tokenManagement.registeredERC20CarbonCredits[tokenConfig.index] != creditToken;
        } else if (tokenType == CommonStructs.TokenType.ERC1155) {
            isFirstRegistration = tokenConfig.index >= tokenManagement.registeredERC1155CarbonCredits.length
                || tokenManagement.registeredERC1155CarbonCredits[tokenConfig.index] != creditToken;
        }

        // Handle first time registration
        if (isFirstRegistration) {
            // Create registration entry
            if (tokenType == CommonStructs.TokenType.ERC20) {
                // For ERC20, ensure tokenIds is either empty or only contains zero
                if (tokenIds.length > 1 || (tokenIds.length == 1 && tokenIds[0] != 0)) {
                    revert Errors.TokenIdMustBeZeroForERC20();
                }

                uint256 newIndex = tokenManagement.registeredERC20CarbonCredits.length;
                tokenManagement.registeredERC20CarbonCredits.push(creditToken);

                // Store the index in the map
                tokenManagement.registeredCarbonCreditsMap[creditToken] = CarbonVaultStorage.RegisteredTokenConfig({
                    index: newIndex,
                    tokenIds: new uint256[](0) // ERC20 doesn't use tokenIds array
                });

                // Store index as 0 for ERC20 (implicit tokenId)
                tokenManagement.tokenIdIndexMap[creditToken][0] = 0;

                return (true); // Success and first registration
            } else if (tokenType == CommonStructs.TokenType.ERC1155) {
                if (tokenIds.length == 0) revert Errors.NoTokensSpecified();
                // ERC1155
                uint256 newIndex = tokenManagement.registeredERC1155CarbonCredits.length;
                tokenManagement.registeredERC1155CarbonCredits.push(creditToken);

                // Create empty token IDs array - will add token IDs below
                tokenManagement.registeredCarbonCreditsMap[creditToken] =
                    CarbonVaultStorage.RegisteredTokenConfig({index: newIndex, tokenIds: new uint256[](0)});
            } else {
                revert Errors.InvalidTokenType();
            }
        } else {
            // For ERC20, subsequent registrations always fail (can only register once)
            if (tokenType == CommonStructs.TokenType.ERC20) {
                return (false);
            }
        }

        // At this point, we're either:
        // 1. A first-time ERC1155 registration that needs token IDs added
        // 2. An existing ERC1155 registration that might need token IDs added

        // For ERC1155, register the token IDs
        bool addedNewTokenId = false;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Skip if already registered
            if (ClassVaultRegistrationUtilsLib.isCarbonCreditRegistered(creditToken, tokenId, tokenType)) {
                continue;
            }

            // Register new token ID
            uint256[] storage tokenIdArray = tokenManagement.registeredCarbonCreditsMap[creditToken].tokenIds;
            uint256 newTokenIdIndex = tokenIdArray.length;

            tokenManagement.tokenIdIndexMap[creditToken][tokenId] = newTokenIdIndex;
            tokenIdArray.push(tokenId);
            addedNewTokenId = true;
        }

        // For ERC1155:
        // - Success = either first-time registration or added at least one new tokenId
        // - Failure = no new tokenIds were added (and not first registration)
        return (isFirstRegistration || addedNewTokenId);
    }

    /**
     * @dev Unregister a carbon credit tokenId from a vault
     * @param creditToken Address of the credit token to unregister
     * @param tokenId The token ID to unregister
     * @param tokenType The token type (ERC20 or ERC1155)
     */
    function unregisterCarbonCredit(address creditToken, uint256 tokenId, CommonStructs.TokenType tokenType) external {
        _requireDelegateCall();

        if (creditToken == address(0)) revert Errors.ZeroAddressNotAllowed();
        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        // Check if token and tokenId are registered
        if (!ClassVaultRegistrationUtilsLib.isCarbonCreditRegistered(creditToken, tokenId, tokenType)) {
            revert Errors.CreditNotRegistered();
        }

        // Check deposit balance - cannot unregister if there are deposits
        if (CarbonVaultStorage.getVaultAccountingStorage().carbonCreditDeposits[creditToken][tokenId] > 0) {
            revert Errors.CarbonVaultHasCredits();
        }

        // Handle based on token type
        if (tokenType == CommonStructs.TokenType.ERC20) {
            // For ERC20, tokenId must be 0 and we're unregistering the entire token
            if (tokenId != 0) revert Errors.TokenIdMustBeZeroForERC20();

            // Get the token's index in the ERC20 array
            uint256 index = tokenManagement.registeredCarbonCreditsMap[creditToken].index;
            uint256 lastIndex = tokenManagement.registeredERC20CarbonCredits.length - 1;

            // Only proceed with swap if this isn't already the last element
            if (index != lastIndex) {
                // Get the last token
                address lastToken = tokenManagement.registeredERC20CarbonCredits[lastIndex];

                // Swap with the last token
                tokenManagement.registeredERC20CarbonCredits[index] = lastToken;

                // Update the index for the swapped token
                tokenManagement.registeredCarbonCreditsMap[lastToken].index = index;
            }

            // Remove the last element
            tokenManagement.registeredERC20CarbonCredits.pop();

            // Clear the token's index mapping
            delete tokenManagement.registeredCarbonCreditsMap[creditToken];
            delete tokenManagement.tokenIdIndexMap[creditToken][0];
        } else if (tokenType == CommonStructs.TokenType.ERC1155) {
            // For ERC1155, we're just unregistering a specific tokenId

            // Get the token's tokenId array
            uint256[] storage tokenIds = tokenManagement.registeredCarbonCreditsMap[creditToken].tokenIds;

            // Get the index of the tokenId to remove
            uint256 tokenIdIndex = tokenManagement.tokenIdIndexMap[creditToken][tokenId];
            uint256 lastTokenIdIndex = tokenIds.length - 1;

            // Only proceed with swap if this isn't already the last element
            if (tokenIdIndex != lastTokenIdIndex) {
                // Get the last tokenId
                uint256 lastTokenId = tokenIds[lastTokenIdIndex];

                // Swap with the last tokenId
                tokenIds[tokenIdIndex] = lastTokenId;

                // Update the index for the swapped tokenId
                tokenManagement.tokenIdIndexMap[creditToken][lastTokenId] = tokenIdIndex;
            }

            // Remove the last element
            tokenIds.pop();

            // Delete the tokenId's index mapping
            delete tokenManagement.tokenIdIndexMap[creditToken][tokenId];

            // If this was the last tokenId for this token, unregister the token entirely
            if (tokenIds.length == 0) {
                // Get the token's index in the ERC1155 array
                uint256 index = tokenManagement.registeredCarbonCreditsMap[creditToken].index;
                uint256 lastIndex = tokenManagement.registeredERC1155CarbonCredits.length - 1;

                // Only proceed with swap if this isn't already the last element
                if (index != lastIndex) {
                    // Get the last token
                    address lastToken = tokenManagement.registeredERC1155CarbonCredits[lastIndex];

                    // Swap with the last token
                    tokenManagement.registeredERC1155CarbonCredits[index] = lastToken;

                    // Update the index for the swapped token
                    tokenManagement.registeredCarbonCreditsMap[lastToken].index = index;
                }

                // Remove the last element
                tokenManagement.registeredERC1155CarbonCredits.pop();

                // Clear the token's registration
                delete tokenManagement.registeredCarbonCreditsMap[creditToken];
            }
        }
    }

    /**
     * @dev Get the count of registered tokenIds for a credit token
     * @param creditToken Address of the credit token
     * @return count Number of registered tokenIds (0 for ERC20 if registered, array length for ERC1155)
     */
    function getRegisteredTokenIdsCount(address creditToken) external view returns (uint256 count) {
        _requireDelegateCall();

        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        return tokenManagement.registeredCarbonCreditsMap[creditToken].tokenIds.length;
    }
}
