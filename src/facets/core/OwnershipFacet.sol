// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../interfaces/IERC173.sol";
import "../../libraries/LibDiamond.sol";

/**
 * @title OwnershipFacet
 * @dev Implementation of the IERC173 interface
 */
contract OwnershipFacet is IERC173 {
    /// @notice Get the address of the owner
    /// @return owner_ The address of the owner
    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    /// @notice Propose a new owner; the new owner must call acceptOwnership() to complete the transfer.
    /// @dev Passing address(0) clears any pending owner without claiming.
    /// @param _newOwner The address of the proposed new owner
    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setPendingContractOwner(_newOwner);
    }

    /// @notice Returns the address of the pending (proposed) owner
    function pendingOwner() external view returns (address) {
        return LibDiamond.pendingContractOwner();
    }

    /// @notice Called by the pending owner to accept ownership and complete the transfer
    function acceptOwnership() external {
        LibDiamond.claimContractOwnership();
    }

    /// @notice Called by the current owner to revoke the pending owner proposal
    function revokePendingOwner() external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setPendingContractOwner(address(0));
    }
}
