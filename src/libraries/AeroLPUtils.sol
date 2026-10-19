// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPool} from "../interfaces/IPool.sol";

/**
 * @title AeroLPUtilsLib
 * @dev Library for LP token utility functions
 * @notice This library provides functions to calculate the total KVCM and K2 in an LP token
 * and the total KVCM and K2 staked in an LP token.
 */
library AeroLPUtilsLib {
    /**
     * @notice Get reserve amount for a specific token in the LP pool
     * @dev Works with any Aerodrome LP pool (KVCM-K2, KVCM-USDC, etc.)
     * @param lpToken Address of the LP token (Aerodrome pool)
     * @param token Address of the token to query reserve for
     * @return Reserve amount of the specified token in the pool, or 0 if token not in pool
     */
    function getReserveForToken(address lpToken, address token) public view returns (uint256) {
        IPool pool = IPool(lpToken);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint256 reserve0 = pool.reserve0();
        uint256 reserve1 = pool.reserve1();

        if (token == token0) {
            return reserve0;
        } else if (token == token1) {
            return reserve1;
        } else {
            return 0;
        }
    }

    /**
     * @notice Get KVCM reserve in the LP pool
     * @dev Convenience wrapper around getReserveForToken for KVCM
     * @param lpToken Address of the LP token (Aerodrome pool)
     * @param kvcmToken Address of the KVCM token
     * @return Reserve amount of KVCM in the pool
     */
    function getKvcmReserveInLp(address lpToken, address kvcmToken) public view returns (uint256) {
        return getReserveForToken(lpToken, kvcmToken);
    }

    /**
     * @notice Get K2 reserve in the LP pool
     * @dev Convenience wrapper around getReserveForToken for K2
     * @param lpToken Address of the LP token (Aerodrome pool)
     * @param k2Token Address of the K2 token
     * @return Reserve amount of K2 in the pool
     */
    function getK2ReserveInLp(address lpToken, address k2Token) public view returns (uint256) {
        return getReserveForToken(lpToken, k2Token);
    }

    /**
     * @notice Get both reserves and token addresses from the LP pool
     * @dev Returns complete pool information in one call
     * @param lpToken Address of the LP token (Aerodrome pool)
     * @return reserve0 Reserve amount of token0
     * @return reserve1 Reserve amount of token1
     * @return token0 Address of token0
     * @return token1 Address of token1
     */
    function getBothReserves(address lpToken)
        public
        view
        returns (uint256 reserve0, uint256 reserve1, address token0, address token1)
    {
        IPool pool = IPool(lpToken);
        token0 = pool.token0();
        token1 = pool.token1();
        reserve0 = pool.reserve0();
        reserve1 = pool.reserve1();
    }
}
