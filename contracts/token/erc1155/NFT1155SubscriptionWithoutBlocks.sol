pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import './NFT1155Upgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT1155SubscriptionWithoutBlocks is NFT1155Upgradeable {
    
//    struct MintedTokens {
//        uint256 amountMinted; // uint64
//        uint256 expirationBlock;
//        uint256 mintBlock;
//        bool isMintOps; // true means mint, false means burn
//    }
//
//    mapping(bytes32 => MintedTokens[]) internal _tokens;

    // It represents the NFT type. It is used to identify the NFT type in the Nevermined ecosystem
    // solhint-disable-next-line
    bytes32 public constant override nftType = keccak256('nft1155-subscription');
    
    function initialize(
        address owner,
        address didRegistryAddress,
        string memory name_,
        string memory symbol_,
        string memory uri_,
        address nvmConfig_
    )
    public
    override
    virtual
    initializer
    {
        __NFT1155Upgradeable_init(owner, didRegistryAddress, name_, symbol_, uri_, nvmConfig_);
    }
    
    
    function mint(address to, uint256 tokenId, uint256 amount, bytes memory data) virtual override public {
        super.mint(to, tokenId, amount, data);
    }    
    
    function mint(address to, uint256 tokenId, uint256 amount, uint256 _expirationBlock, bytes memory data) virtual public {
        super.mint(to, tokenId, amount, data);
    } 

    function burn(uint256 id, uint256 amount) override public {
        burn(_msgSender(), id, amount);
    }

    // solhint-disable-next-line
    function burn(address to, uint256 id, uint256 amount) override public {
        address _sender = _msgSender();
        require(balanceOf(to, id) >= amount, 'ERC1155: burn amount exceeds balance');
        require(
            isOperator(_sender) || // Or the DIDRegistry is burning the NFT 
            to == _sender || // Or the NFT owner is _msgSender() 
            nftRegistry.isDIDProvider(bytes32(id), _sender) || // Or the DID Provider (Node) is burning the NFT
            isApprovedForAll(to, _sender), // Or the _msgSender() is approved
            'ERC1155: caller is not owner nor approved'
        );

        // Update nftSupply
        _nftAttributes[id].nftSupply -= amount;
        // Register provenance event

        _burn(to, id, amount);
    }    
    
    /**
     * @dev See {NFT1155Upgradeableable-balanceOf}.
     */
    function balanceOf(address account, uint256 tokenId) public view virtual override returns (uint256) {
        return super.balanceOf(account, tokenId);
//        bytes32 _key = _getTokenKey(account, tokenId);
//        uint256 _amountBurned;
//        uint256 _amountMinted;
//        for (uint index = 0; index < _tokens[_key].length; index++) {
//            if (_tokens[_key][index].mintBlock > 0 &&
//                (_tokens[_key][index].expirationBlock == 0 || _tokens[_key][index].expirationBlock > block.number)) {
//                if (_tokens[_key][index].isMintOps)
//                    _amountMinted += _tokens[_key][index].amountMinted;
//                else
//                    _amountBurned += _tokens[_key][index].amountMinted;
//            }
//        }
//
//        if (_amountBurned >= _amountMinted)
//            return 0;
//        else
//            return _amountMinted - _amountBurned;
    }
    
//    function whenWasMinted(address owner, uint256 tokenId) public view returns (uint256[] memory) {
//        bytes32 _key = _getTokenKey(owner, tokenId);
//        uint256[] memory _whenMinted = new uint256[](_tokens[_key].length);
//        for (uint index = 0; index < _tokens[_key].length; index++) {
//            _whenMinted[index] = _tokens[_key][index].mintBlock;
//        }
//        return _whenMinted;
//    }
//    
//    function getMintedEntries(address owner, uint256 tokenId) public view returns (MintedTokens[] memory) {
//        return _tokens[_getTokenKey(owner, tokenId)];
//    }
//    
//    function _getTokenKey(address account, uint256 tokenId) internal pure returns (bytes32) {
//        return keccak256(abi.encode(account, tokenId));
//    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        require(ids.length == amounts.length, 'mintBatch: lengths do not match');
        for (uint i = 0; i < ids.length; i++) {
            mint(to, ids[i], amounts[i], data);
        }
    }

    function burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external {
        require(ids.length == amounts.length, 'burnBatch: lengths do not match');
        for (uint i = 0; i < ids.length; i++) {
            burn(from, ids[i], amounts[i]);
        }
    }

    function burnBatchFromHolders(
        address[] memory from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external {
        require(ids.length == amounts.length, 'burnBatch: lengths do not match');
        require(ids.length == from.length, 'burnBatch: lengths do not match');
        for (uint i = 0; i < ids.length; i++) {
            burn(from[i], ids[i], amounts[i]);
        }
    }
}
