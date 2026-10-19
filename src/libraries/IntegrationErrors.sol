// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IntegrationErrors
 * @notice Central catalogue of custom errors for integration with external systems
 */
library IntegrationErrors {
    /*//////////////////////////////////////////////////////////////////////////
                                ZK.ME
    //////////////////////////////////////////////////////////////////////////*/
    error ZkMeNotVerified(address user);
}
