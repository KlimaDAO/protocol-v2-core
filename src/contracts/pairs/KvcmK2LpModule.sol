// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseLpStakingCore.sol";

/**
 * @title KvcmK2LpModule
 * @dev Facet for KVCM-K2 LP token staking
 */
contract KvcmK2LpModule is BaseLpStakingCore {
    using SafeERC20 for IERC20;
}
