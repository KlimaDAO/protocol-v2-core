// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IKVCM
 * @dev Interface for the Kvcm token contract
 */
interface IKVCM is IERC20 {
    /**
     * @notice Mint tokens to a specific address
     * @dev Only callable by addresses with MINTER_ROLE
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn tokens from caller's balance
     * @dev Only callable by addresses with BURNER_ROLE
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Burn tokens from a specific account
     * @dev Only callable by addresses with BURNER_ROLE
     * @param account The account to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external;
}
