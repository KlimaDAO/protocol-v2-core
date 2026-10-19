// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../libraries/CarbonVaultStorage.sol";
import "../libraries/Errors.sol";
import "../libraries/CommonStructs.sol";
import "../interfaces/ICarbonLedger.sol";
import "../interfaces/ICarbonClassVault.sol";

/**
 * @title ClassVaultRegistrationUtilsLib
 * @dev Library for checking if a carbon credit token and tokenId combination is registered in a CarbonClassVault
 */
library ClassVaultRegistrationUtilsLib {
    /**
     * @dev Check if a credit token and tokenId combination is registered in this vault
     * @param creditToken Address of the credit token to check
     * @param tokenId The token ID to check
     * @return bool True if the credit/tokenId is registered
     */
    function isCarbonCreditRegistered(address creditToken, uint256 tokenId, CommonStructs.TokenType tokenType)
        public
        view
        returns (bool)
    {
        return _isCarbonCreditRegistered(creditToken, tokenId, tokenType);
    }

    function _isCarbonCreditRegistered(address creditToken, uint256 tokenId, CommonStructs.TokenType tokenType)
        internal
        view
        returns (bool)
    {
        CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
            CarbonVaultStorage.getTokenManagementStorage();

        // First check if the token itself is registered
        CarbonVaultStorage.RegisteredTokenConfig storage tokenConfig =
            tokenManagement.registeredCarbonCreditsMap[creditToken];

        bool isTokenRegistered = false;

        // Check if token is registered at the token level
        if (tokenType == CommonStructs.TokenType.ERC1155) {
            isTokenRegistered = tokenConfig.index < tokenManagement.registeredERC1155CarbonCredits.length
                && tokenManagement.registeredERC1155CarbonCredits[tokenConfig.index] == creditToken;
        } else if (tokenType == CommonStructs.TokenType.ERC20) {
            isTokenRegistered = tokenConfig.index < tokenManagement.registeredERC20CarbonCredits.length
                && tokenManagement.registeredERC20CarbonCredits[tokenConfig.index] == creditToken;
        }

        // If token is registered, check if the specific tokenId is registered
        if (isTokenRegistered) {
            // For ERC20, we need to check tokenId is 0 as that's the only valid tokenId
            if (tokenType == CommonStructs.TokenType.ERC20) {
                return tokenId == 0; // Only tokenId 0 is valid for ERC20
            } else {
                // For ERC1155, check the specific tokenId using the index map
                uint256 index = tokenManagement.tokenIdIndexMap[creditToken][tokenId];
                uint256[] storage tokenIds = tokenConfig.tokenIds;

                // Valid if index is in bounds and the tokenId at that index matches the requested tokenId
                return index < tokenIds.length && tokenIds[index] == tokenId;
            }
        }

        return false;
    }
}
