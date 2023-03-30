pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import './NFT1155Upgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT1155SubscriptionUpgradeable is NFT1155Upgradeable {

    struct MintedTokens {
        uint256 amountMinted;
        uint256 expirationBlock;
        uint256 mintBlock;
    }

    mapping(bytes32 => MintedTokens[]) internal _tokens;
    
    /**
     * @dev This mint function allows to define when the tokenId of the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     */
    function mint(address to, uint256 tokenId, uint256 amount, uint256 expirationBlock, bytes memory data) public virtual {
        super.mint(to, tokenId, amount, data);
        bytes32 _key = _getTokenKey(to, tokenId);

        _tokens[_key].push( MintedTokens(amount, expirationBlock, block.number));
    }

    function burn(uint256 id, uint256 amount) override public {
        burn(_msgSender(), id, amount);
    }    
    
    function burn(address to, uint256 id, uint256 amount) override public {
        require(super.balanceOf(to, id) >= amount, 'ERC1155: burn amount exceeds balance');
        require(
            isOperator(_msgSender()) || // Or the DIDRegistry is burning the NFT 
            to == _msgSender() || // Or the NFT owner is _msgSender() 
            isApprovedForAll(to, _msgSender()), // Or the _msgSender() is approved
            'ERC1155: caller is not owner nor approved'
        );

        // Update nftSupply
        _nftAttributes[id].nftSupply -= amount;
        // Register provenance event
        nftRegistry.used(
            keccak256(abi.encode(id, _msgSender(), 'burn', amount, block.number)),
            bytes32(id), _msgSender(), keccak256('burn'), '', 'burn');
        
        bytes32 _key = _getTokenKey(to, id);
        
        uint256 _pendingToBurn = amount;
        for (uint index = 0; index < _tokens[_key].length; index++) {
            if (_pendingToBurn <= _tokens[_key][index].amountMinted) {
                _tokens[_key][index].amountMinted -= _pendingToBurn;
                break;
            } else {
                _pendingToBurn -= _tokens[_key][index].amountMinted;
                //_tokens[_key][index].amountMinted = 0;
                delete _tokens[_key][index];
            }
        }
    }    
    
    /**
     * @dev See {NFT1155Upgradeableable-balanceOf}.
     */
    function balanceOf(address account, uint256 tokenId) public view virtual override returns (uint256) {
        bytes32 _key = _getTokenKey(account, tokenId);
        uint256 _balance;
        for (uint index = 0; index < _tokens[_key].length; index++) {
            if (_tokens[_key][index].mintBlock > 0 && 
                (_tokens[_key][index].expirationBlock == 0 || _tokens[_key][index].expirationBlock > block.number))
                _balance += _tokens[_key][index].amountMinted;
        }
        
        return _balance;
    }
    
    function whenWasMinted(address owner, uint256 tokenId) public view returns (uint256[] memory) {
        bytes32 _key = _getTokenKey(owner, tokenId);
        uint256[] memory _whenMinted = new uint256[](_tokens[_key].length);
        for (uint index = 0; index < _tokens[_key].length; index++) {
            _whenMinted[index] = _tokens[_key][index].mintBlock;
        }
        return _whenMinted;
    }
    
    function getMintedEntries(address owner, uint256 tokenId) public view returns (MintedTokens[] memory) {
        return _tokens[_getTokenKey(owner, tokenId)];
    }
    
    function _getTokenKey(address account, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, tokenId));
    }
}
