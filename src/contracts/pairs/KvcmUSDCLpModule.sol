// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseLpStakingCore.sol";

/**
 * @title KvcmUSDCLpModule
 * @dev Facet for KVCM-USDC LP token staking with specific validation and reward logic
 */
contract KvcmUSDCLpModule is BaseLpStakingCore {
    using SafeERC20 for IERC20;
}
