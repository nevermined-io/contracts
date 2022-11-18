// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import '../NFTBase.sol';

/**
 *
 * @dev Implementation of the basic standard multi-token.
 * See https://eips.ethereum.org/EIPS/eip-1155
 */
contract NFTUpgradeable is ERC1155Upgradeable, NFTBase {

    // Token name
    string public name;

    // Token symbol
    string public symbol;    
    
    function initializeWithName(
        string memory name_,
        string memory symbol_,
        string memory uri_
    )
    public
    virtual
    initializer  
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC1155_init_unchained(uri_);
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(MINTER_ROLE, msg.sender);
        setContractMetadataUri(uri_);
        name = name_;
        symbol = symbol_;
    }
    
    // solhint-disable-next-line
    function initialize(string memory uri_) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC1155_init_unchained(uri_);
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(MINTER_ROLE, _msgSender());
        setContractMetadataUri(uri_);
        name = 'Nevermined ERC1155';
        symbol = 'NVM1155';        
    }
    
    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return super.isApprovedForAll(account, operator) || _proxyApprovals[operator];
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory data) public {
        require(hasRole(MINTER_ROLE, _msgSender()), 'only minter can mint');
        _mint(to, id, amount, data);
    }

    function burn(address to, uint256 id, uint256 amount) public {
        require(balanceOf(to, id) >= amount, 'ERC1155: burn amount exceeds balance');
        require(
            hasRole(MINTER_ROLE, _msgSender()) || // Or the DIDRegistry is burning the NFT 
            to == _msgSender() || // Or the NFT owner is _msgSender() 
            isApprovedForAll(to, _msgSender()), // Or the _msgSender() is approved
            'ERC1155: caller is not owner nor approved'
        );
        _burn(to, id, amount);
    }

    function addMinter(address account) public onlyOwner {
        AccessControlUpgradeable._setupRole(MINTER_ROLE, account);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return _metadata[tokenId].nftURI;
    }
    
    /**
    * @dev Record some NFT Metadata
    * @param tokenId the id of the asset with the royalties associated
    * @param nftURI the URI (https, ipfs, etc) to the metadata describing the NFT
    */
    function setNFTMetadata(
        uint256 tokenId,
        string memory nftURI
    )
    public
    {
        require(hasRole(MINTER_ROLE, _msgSender()), 'only minter');
        _setNFTMetadata(tokenId, nftURI);
    }    
    
    /**
    * @dev Record the asset royalties
    * @param tokenId the id of the asset with the royalties associated
    * @param receiver the receiver of the royalties (the original creator)
    * @param royaltyAmount percentage (no decimals, between 0 and 100)    
    */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint256 royaltyAmount
    ) 
    public
    {
        require(hasRole(MINTER_ROLE, _msgSender()), 'only minter');
        _setTokenRoyalty(tokenId, receiver, royaltyAmount);
    }
    
    function supportsInterface(
        bytes4 interfaceId
    ) 
    public 
    view 
    virtual 
    override(ERC1155Upgradeable, AccessControlUpgradeable, IERC165Upgradeable) 
    returns (bool) 
    {
        return AccessControlUpgradeable.supportsInterface(interfaceId)
        || ERC1155Upgradeable.supportsInterface(interfaceId)
        || interfaceId == type(IERC2981Upgradeable).interfaceId;
    }
    
    function _msgSender() internal override(NFTBase,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(NFTBase,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }

    /**
    * @dev It protects NFT transfers to force going through service agreements and enforce royalties
    */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
    internal
    virtual
    override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        require(
            from == address(0) || // We exclude mints
            to == address(0) || // We exclude burns
            isApprovedProxy(_msgSender()) // Only proxies (Nevermined condition contracts)
            , 'only proxy'
        );
    }    
    
}
