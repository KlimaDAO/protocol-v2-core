// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "../../libraries/Errors.sol";
import "../../libraries/CarbonSystemRoleLib.sol";
import {ICommonEvents} from "../../interfaces/ICommonEvents.sol";

/**
 * @title KvcmLocks
 * @dev Upgradeable ERC721 contract for Kvcm Locks with restricted transfers
 * Transfers are only allowed when initiated by an address with the KVCM_LOCK_NFT_MANAGER role
 */
contract KvcmLockNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 constant KVCM_LOCK_NFT_STORAGE = keccak256("kvcm-lock-nft.storage");

    struct KvcmLockNFTConfig {
        address accessManager;
        uint256[50] _gap;
    }

    function managerConfigLayout() internal pure returns (KvcmLockNFTConfig storage l) {
        bytes32 position = KVCM_LOCK_NFT_STORAGE;
        assembly {
            l.slot := position
        }
    }

    modifier onlyLiquidityManager() {
        if (!_isLiquidityManager()) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyOwner() {
        if (!_isOwner()) revert Errors.NotAuthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address accessManager_) external initializer {
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        managerConfigLayout().accessManager = accessManager_;
    }

    function _isLiquidityManager() internal view returns (bool) {
        IAccessManager am = IAccessManager(managerConfigLayout().accessManager);
        (bool hasManagerRole,) = am.hasRole(CarbonSystemRoleLib.KVCM_LOCK_NFT_MANAGER, msg.sender);
        return hasManagerRole;
    }

    function _isOwner() internal view returns (bool) {
        IAccessManager am = IAccessManager(managerConfigLayout().accessManager);
        (bool hasOwnerRole,) = am.hasRole(CarbonSystemRoleLib.KVCM_LOCK_NFT_OWNER, msg.sender);
        return hasOwnerRole;
    }

    /**
     * @dev Mint a new lock NFT
     * @param to Address to mint the lock to
     * @param tokenId ID of the token to mint
     * @param uri Token URI for metadata
     */
    function mint(address to, uint256 tokenId, string memory uri) external onlyLiquidityManager {
        if (to == address(0)) revert Errors.ZeroAddressNotAllowed();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    // Check the standard practises..
    /**
     * @dev Burn a lock NFT
     * @param tokenId ID of the token to burn
     */
    function burn(uint256 tokenId) external onlyLiquidityManager {
        _burn(tokenId);
    }

    /**
     * @dev Override transfer functions to enforce restrictions
     */
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable) returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            // For regular transfers, enforce restrictions
            if (!_isTransferAllowed(from, to)) {
                revert Errors.TransfersNotAllowed();
            }
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override for token URI functionality
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Override for interface support
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Authorization for UUPS upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _isTransferAllowed(address from, address to) internal view returns (bool) {
        // Minting and burning bypass transfer restrictions
        if (from == address(0) || to == address(0)) return true;

        // Regular transfers require caller to have KVCM_LOCK_NFT_MANAGER role
        return _isLiquidityManager();
    }

    function setAccessManager(address accessManager_) external onlyOwner {
        if (accessManager_ == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (accessManager_.code.length == 0) revert Errors.NoCodeAtAddress(accessManager_);
        managerConfigLayout().accessManager = accessManager_;
        emit ICommonEvents.AccessManagerUpdated(accessManager_);
    }
}
