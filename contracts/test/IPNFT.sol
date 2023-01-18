//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

contract IPNFT is ERC721URIStorageUpgradeable, OwnableUpgradeable {
    // Events
    event TokenURIChanged(uint256 tokenId, string indexed newURI);

    //calling constructor from this contract plus ERC721 constructor
    function initialize(string memory _name, string memory _symbol) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(_name, _symbol);
        __Ownable_init_unchained();
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI)
        public
        onlyOwner
    {
        _setTokenURI(tokenId, _tokenURI);
        emit TokenURIChanged(tokenId, _tokenURI);
    }

    // default mint is minting with tokenURI
    function mint(
        address to,
        uint256 _tokenId,
        string memory _tokenURI
    ) public returns (bool) {
        _safeMint(to, _tokenId);
        setTokenURI(_tokenId, _tokenURI);

        return true;
    }

    // there is an option to mint the NFT without the tokenURI if needed too
    function mintWithoutTokenURI(address to, uint256 _tokenId)
        external
        onlyOwner
    {
        _safeMint(to, _tokenId);
    }

    function transfer(
        address from,
        address to,
        uint256 _tokenId
    ) public {
        safeTransferFrom(from, to, _tokenId);
    }

}
