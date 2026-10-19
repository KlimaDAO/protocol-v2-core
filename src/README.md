# Carbon Credit System

This directory contains the implementation of a Carbon Credit Ledger and Vault system for managing carbon credit tokens.

## Contracts

### CarbonLedger

The `CarbonLedger` contract serves as the main registry and manager for carbon credit class vaults. It enables the following functionality:

- Registration and management of carbon class vaults
- Whitelisting and blacklisting of carbon credit tokens for specific classes
- Movement of carbon credits between different class vaults
- Management of liquidity for carbon credit tokens
- Role-based access control for admin and manager functions

### CarbonClassVault

The `CarbonClassVault` contract serves as a vault for storing carbon credit tokens for a specific carbon class. It supports:

- Storing both ERC20 and ERC1155 carbon credit tokens
- Conversion between token amounts and carbon tonnes based on configurable rates
- Deposit and withdrawal of tokens
- Tracking of token balances
- Dust handling for small amounts

## Architecture

The system follows a hierarchical design where:

1. The `CarbonLedger` is the top-level contract that manages the overall system
2. Multiple `CarbonClassVault` instances can be created, each representing a different carbon credit class
3. Each vault can hold multiple types of carbon credit tokens (ERC20 or ERC1155)

## Key Features

- Support for both ERC20 and ERC1155 carbon credit tokens
- Configurable conversion rates for different tokens
- Whitelisting and blacklisting mechanisms for security
- Role-based access control for administrative functions
- Migration of credits between vaults
- Tracking of carbon credit balances in tonnes

## Usage Example

```solidity
// Deploy the CarbonLedger
CarbonLedger ledger = new CarbonLedger();

// Create a new Carbon Class Vault
CarbonClassVault vault = new CarbonClassVault("Forest Carbon Credits", msg.sender, address(ledger));
address vaultAddress = address(vault);
ledger.registerClass(vaultAddress);

// Onboard a carbon credit token to the class
ledger.addCreditConfig(vaultAddress, tokenAddress);

// Add liquidity to the class vault
ledger.addCreditLiquidityToClassVault(vaultAddress, tokenAddress, amount);

// Get the total carbon credits in the vault
uint256 totalCredits = ICarbonClassVault(vaultAddress).totalCredits();
``` 