// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library CarbonVaultSynchronizerLib {}
// /**
//  * @dev Recalculates the total tonnes based on current deposits and conversion rates.
//  *      Useful for verification. NOTE: Will cause addition gas.
//  * @return Recalculated total carbon credits in tonnes (scaled by precision).
//  */
// function calculateCurrentTotalTonnes() public view returns (uint256) {
//     CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
//         CarbonVaultStorage.getTokenManagementStorage();
//     uint256 calculatedTotalTonnes = 0;

//     // Process ERC20 tokens (simple, just tokenId 0)
//     for (uint256 i = 0; i < tokenManagement.registeredERC20CarbonCredits.length; i++) {
//         address creditToken = tokenManagement.registeredERC20CarbonCredits[i];
//         CommonStructs.CreditConfig memory config = tokenManagement.creditConfigs[creditToken];

//         if (config.conversion.tonnesPerUnit > 0) {
//             uint256 amount = tokenManagement.carbonCreditDeposits[creditToken][0];
//             if (amount > 0) {
//                 calculatedTotalTonnes += CarbonTonnageLib.tokenAmountToTonnes(amount, config.conversion);
//             }
//         }
//     }

//     // Process ERC1155 tokens (need to check all tokenIds)
//     for (uint256 i = 0; i < tokenManagement.registeredERC1155CarbonCredits.length; i++) {
//         address creditToken = tokenManagement.registeredERC1155CarbonCredits[i];
//         CommonStructs.CreditConfig memory config = tokenManagement.creditConfigs[creditToken];

//         if (config.conversion.tonnesPerUnit > 0) {
//             uint256[] memory tokenIds = tokenManagement.registeredCarbonCreditsMap[creditToken].tokenIds;

//             for (uint256 j = 0; j < tokenIds.length; j++) {
//                 uint256 tokenId = tokenIds[j];
//                 uint256 amount = tokenManagement.carbonCreditDeposits[creditToken][tokenId];
//                 if (amount > 0) {
//                     calculatedTotalTonnes += CarbonTonnageLib.tokenAmountToTonnes(amount, config.conversion);
//                 }
//             }
//         }
//     }

//     return calculatedTotalTonnes;
// }

// /**
//  * @dev Synchronizes the internally tracked _totalTonnes with a fresh calculation.
//  *      Can only be called by the owner. Useful to correct potential drift.
//  */
// function syncTotalTonnes() external onlyOwner {
//     uint256 calculatedTotal = calculateCurrentTotalTonnes();
//     CarbonVaultStorage.getTonnesAccountingStorage().totalTonnes = calculatedTotal;
//     emit TotalTonnesSynced(calculatedTotal);
// }

// /**
//  * @dev Synchronizes the internally tracked _totalTonnes for specific credit tokens.
//  *      Can only be called by the owner. Useful to correct potential drift or account for admin-burnt tokens.
//  * @param creditTokens Array of credit token addresses to sync
//  * @param tokenIds Array of token IDs corresponding to each credit token (use 0 for ERC20)
//  */
// function rebalanceVaultTokenTonnes(address[] calldata creditTokens, uint256[] calldata tokenIds)
//     external
//     onlyOwner
// {
//     CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
//         CarbonVaultStorage.getTokenManagementStorage();
//     CarbonVaultStorage.TonnesAccountingStorage storage tonnesAccounting =
//         CarbonVaultStorage.getTonnesAccountingStorage();

//     if (creditTokens.length == 0) revert CarbonErrors.NoTokensSpecified();
//     if (creditTokens.length != tokenIds.length) revert CarbonErrors.ArraysLengthMismatch();

//     uint256 oldTotal = tonnesAccounting.totalTonnes;
//     uint256 newTotalContribution = 0;

//     for (uint256 i = 0; i < creditTokens.length; i++) {
//         address token = creditTokens[i];
//         uint256 tokenId = tokenIds[i];

//         // Get the asset config
//         CommonStructs.CreditConfig storage config = tokenManagement.creditConfigs[token];
//         if (config.conversion.tonnesPerUnit == 0) revert CarbonErrors.CreditNotRegistered();

//         uint256 actualAmount;
//         if (config.tokenType == CommonStructs.TokenType.ERC1155) {
//             // For ERC1155, get the balance from contract or our tracking
//             // ERC1155 token IDs can be 0 - removed incorrect validation
//             // if (tokenId == 0) revert CarbonErrors.InvalidTokenId();
//             actualAmount = IERC1155(token).balanceOf(address(this), tokenId);

//             // Update our tracking to match the actual balance
//             uint256 oldTrackedAmount = tokenManagement.carbonCreditDeposits[token][tokenId];
//             tokenManagement.carbonCreditDeposits[token][tokenId] = actualAmount;

//             // Update the total deposit tracking for this token
//             // config.totalDeposited = config.totalDeposited + actualAmount - oldTrackedAmount;
//         } else {
//             // For ERC20, get the balance from contract
//             actualAmount = IERC20(token).balanceOf(address(this));

//             // Update our tracking to match the actual balance
//             // config.totalDeposited = actualAmount;
//         }

//         // Calculate tonnes contribution for this token
//         uint256 newTonnesContribution = CarbonTonnageLib.tokenAmountToTonnes(actualAmount, config.conversion);
//         newTotalContribution += newTonnesContribution;
//     }

//     // Update the total tonnes
//     tonnesAccounting.totalTonnes = newTotalContribution;

//     emit TokenTonnesRebalanced(creditTokens, tokenIds, oldTotal, newTotalContribution);
// }

// /**
//  * @dev Verifies if the internally tracked total tonnes matches the recalculated total.
//  * @return calculatedTotal The recalculated total tonnes.
//  * @return trackedTotal The internally tracked total tonnes (_totalTonnes).
//  * @return matches True if the calculated and tracked totals match.
//  */
// function calculateAndVerifyTotalTonnes()
//     external
//     view
//     returns (uint256 calculatedTotal, uint256 trackedTotal, bool matches)
// {
//     calculatedTotal = calculateCurrentTotalTonnes();
//     trackedTotal = CarbonVaultStorage.getTonnesAccountingStorage().totalTonnes;
//     matches = (calculatedTotal == trackedTotal);
//     return (calculatedTotal, trackedTotal, matches);
// }

// /**
//  * @dev Returns a list of tokenIds that are registered for this credit token.
//  * @param creditToken The address of the ERC1155 credit token.
//  * @return An array of tokenIds that are registered for this credit token.
//  */
// function getRegisteredTokenIds(address creditToken) external view override returns (uint256[] memory) {
//     CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
//         CarbonVaultStorage.getTokenManagementStorage();

// /**
//  * @dev Matures forward carbon when its maturity date is reached
//  * @param maturityId The maturity ID to mature
//  *
//  * TODO: Optimize for gas efficiency. The current implementation may hit block gas limits
//  * with a large number of tokens due to the unbounded loops. Consider:
//  * 1. Implementing a token-specific maturation function
//  * 2. Adding batch processing capability
//  * 3. Using lazy evaluation during withdrawals
//  */
// function matureForwardCarbon(uint256 maturityId) external onlyCarbonLedger nonReentrant {
//     CarbonVaultStorage.VaultConfigStorage storage vaultConfig = CarbonVaultStorage.getVaultConfigStorage();
//     CarbonVaultStorage.MaturityAccountingStorage storage maturityAccounting =
//         CarbonVaultStorage.getMaturityAccountingStorage();
//     CarbonVaultStorage.TokenManagementStorage storage tokenManagement =
//         CarbonVaultStorage.getTokenManagementStorage();

//     // Get maturity timestamp
//     address maturityManagerAddr = vaultConfig.maturityManager;
//     if (maturityManagerAddr == address(0)) {
//         revert CarbonErrors.MaturityManagerNotSet();
//     }

//     uint256 maturityTimestamp = IMaturityManager(maturityManagerAddr).getMaturityTimestamp(maturityId);

//     // Get current maturity ID
//     uint256 currentMaturityId = IMaturityManager(maturityManagerAddr).getFirstActiveMaturityId();

//     // Only mature if maturity is now active/current
//     if (maturityId > currentMaturityId) {
//         revert CarbonErrors.MaturityNotReached(maturityId, maturityTimestamp);
//     }

//     // Get tonnes for this maturity
//     uint256 maturityTonnes = maturityAccounting.maturityTonnes[maturityId];

//     // Check if already matured (no liquid tonnes to add)
//     if (maturityTonnes == 0) {
//         revert CarbonErrors.NoTonnesToMature();
//     }

//     // Transfer aggregate tonnes from maturity to liquid accounting
//     maturityAccounting.liquidTonnes += maturityTonnes;
//     // Clear maturity tonnes after transferring to liquid
//     maturityAccounting.maturityTonnes[maturityId] = 0;

//     // Process all ERC20 token credits
//     for (uint256 i = 0; i < tokenManagement.registeredERC20CarbonCredits.length; i++) {
//         address tokenAddr = tokenManagement.registeredERC20CarbonCredits[i];
//         uint256 tokenId = 0; // ERC20 always uses tokenId 0

//         uint256 tokenMaturityTonnes = maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId];
//         if (tokenMaturityTonnes > 0) {
//             // Transfer tonnes from maturity accounting to liquid accounting
//             maturityAccounting.liquidTokenTonnes[tokenAddr][tokenId] += tokenMaturityTonnes;
//             // Clear maturity-specific token tonnes after transferring to liquid
//             maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId] = 0;
//         }
//     }

//     // Process all ERC1155 token credits
//     for (uint256 i = 0; i < tokenManagement.registeredERC1155CarbonCredits.length; i++) {
//         address tokenAddr = tokenManagement.registeredERC1155CarbonCredits[i];
//         uint256[] memory tokenIds = tokenManagement.registeredCarbonCreditsMap[tokenAddr].tokenIds;

//         for (uint256 j = 0; j < tokenIds.length; j++) {
//             uint256 tokenId = tokenIds[j];
//             uint256 tokenMaturityTonnes = maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId];

//             if (tokenMaturityTonnes > 0) {
//                 // Transfer tonnes from maturity accounting to liquid accounting
//                 maturityAccounting.liquidTokenTonnes[tokenAddr][tokenId] += tokenMaturityTonnes;
//                 // Clear maturity-specific token tonnes after transferring to liquid
//                 maturityAccounting.maturityTokenTonnes[maturityId][tokenAddr][tokenId] = 0;
//             }
//         }
//     }

//     emit ForwardCarbonMatured(maturityId, maturityTonnes);
