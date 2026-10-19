# Functions in CarbonClassVault and CarbonClassCoupons

## CarbonClassVault Functions

| Function Name | Visibility | Description |
|---------------|------------|-------------|
| `constructor()` | public | Empty constructor for upgradeable contracts |
| `initialize(string, address, address)` | external | Initializes the contract for use with a proxy |
| `registerCarbonCredit(address, uint256[], TokenType)` | external | Register a carbon credit token for use with this vault |
| `unregisterCarbonCredit(address, uint256)` | external | Unregister a carbon credit tokenId from this vault |
| `depositCarbonCredits(address, uint256, uint256, address, uint256)` | external | Deposit carbon credits into the vault |
| `withdrawCarbonCredits(address, uint256, uint256, uint256, address)` | external | Withdraw carbon credits directly without checking registration |
| `accessManager()` | public | Returns the current access manager address |
| `setAccessManager(address)` | external | Sets a new access manager for the vault |
| `getTotalTonnes()` | external | Get the total amount of carbon credits in the vault in tonnes |
| `balanceCarbonCredits(address, uint256)` | external | Get the balance of a specific carbon credit token |
| `getCarbonCreditConfig(address)` | external | Get the configuration of a specific credit token |
| `getClassVaultInfo()` | external | Get information about the vault |
| `getMaturityTonnes(uint256)` | external | Get the total tonnes for a specific maturity ID |
| `getMaturitiesTonnes(uint256[])` | external | Get tonnage amounts for multiple maturity IDs at once |
| `getTokenTonnesByMaturity(uint256, address, uint256)` | external | Get the tonnes for a specific maturity, token address and token ID |
| `getVaultTonnes(uint256[])` | external | Returns various tonnage metrics for the vault |
| `convertTonnesToTokenAmount(uint256, address, uint256)` | public | Converts tonnes to token amount |
| `name()` | public | Override ERC20Upgradeable name() |
| `getAvailableTonnes()` | public | Gets the amount of tonnes available (not reserved for coupons) |
| `hasEnoughAvailableTonnes(uint256)` | public | Checks if there are enough available tonnes |
| `carbonLedger()` | public | Get carbon ledger address |
| `onERC1155Received(address, address, uint256, uint256, bytes)` | public | Implements IERC1155Receiver for single token transfers |
| `onERC1155BatchReceived(address, address, uint256[], uint256[], bytes)` | public | Implements IERC1155Receiver for batch token transfers |
| `supportsInterface(bytes4)` | public | Properly implement ERC165 pattern |
| `_depositCredits(address, uint256, uint256, address, uint256)` | internal | Internal logic for depositing carbon credits |
| `_withdrawCarbonCredits(address, uint256, uint256, uint256, address)` | internal | Internal implementation for withdrawing carbon credits |
| `_authorizeUpgrade(address)` | internal | Authorizes an upgrade to a new implementation |
| `_convertTonnesToTokenAmount(uint256, address, uint256)` | internal | Internal function to convert tonnes to token amount |
| `getLiquidTonnes()` | public | Returns the amount of liquid tonnes in the vault |
| `getLiquidTokenTonnes(address, uint256)` | public | Returns the liquid tonnes for a specific token |
| `setMaturityManager(address)` | external | Sets the maturity manager address |
| `getRegisteredTokenIds(address)` | external | Returns a list of tokenIds that are registered for this credit token |

## CarbonClassCoupons Functions

| Function Name | Visibility | Description |
|---------------|------------|-------------|
| `constructor()` | public | Empty constructor for upgradeable contracts |
| `initialize(string, string)` | external | Standard initializer for the upgradeable contract pattern |
| `initializeCouponSystem(string, string, address)` | external | Initializes the coupon system with rewards manager |
| `issueCoupons(address, uint256)` | external | Issues coupons to an account |
| `burnCoupons(address, uint256)` | external | Burns coupons and releases reserved tonnes |
| `setRewardManager(address)` | external | Sets a new rewards manager address |
| `getReservedTonnes()` | public | Returns the total amount of tonnes reserved for coupons |
| `isCouponSystemInitialized()` | external | Checks if the coupon system has been initialized |
| `getRewardManager()` | external | Gets the current rewards manager address |
