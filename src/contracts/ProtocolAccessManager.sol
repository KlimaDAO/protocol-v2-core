// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title ProtocolAccessManager
 * @dev Non-upgradeable version of AccessManager for the Carbon protocol.
 * Manages role-based permissions for the entire system.
 */
contract ProtocolAccessManager is AccessManager {
    /**
     * @dev Constructor that sets the initial admin
     * @param initialAdmin The initial admin address that will have ADMIN_ROLE permissions
     */
    constructor(address initialAdmin) AccessManager(initialAdmin) {}
}
