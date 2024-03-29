pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../interfaces/IRoyaltyScheme.sol';
import '../registry/DIDRegistry.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol';

/**
 * @title Royalties scheme with bonding curve.
 * @author Nevermined
 */

contract CurveRoyalties is IRoyaltyScheme, Initializable, Common {

    DIDRegistry public registry;

    uint256 constant public DENOMINATOR = 1000000;

    mapping (bytes32 => uint256) public royalties;

    function initialize(address _registry) public initializer {
        registry = DIDRegistry(_registry);
    }

    function royaltyCurve(uint256 num, uint256 max, uint256 rate) public pure virtual returns (uint256) {
        return rate * (max-num) / max;
    }

    /**
     * @notice Set royalties for a DID
     * @dev Can only be called by creator of the DID
     * @param _did DID for which the royalties are set
     * @param _royalty Royalty, the actual royalty will be _royalty / 10000 percent
     */
    function setRoyalty(bytes32 _did, uint256 _royalty) public {
        require(_royalty <= DENOMINATOR, 'royalty cannot be more than 100%');
        require(_msgSender() == registry.getDIDCreator(_did), 'only owner can change');
        require(royalties[_did] == 0, 'royalties cannot be changed');
        royalties[_did] = _royalty;
    }

    function check(bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _token)
    external view returns (bool)
    {
        (address nftContractAddress,) = registry.getNFTInfo(_did);
        
        if (_token != nftContractAddress) {
            return false;
        }
        NFT1155Upgradeable _nftInstance = NFT1155Upgradeable(nftContractAddress);
        (,uint256 supply,uint256 cap,) = _nftInstance.getNFTAttributes(uint256(_did));
        
        // If there are no royalties everything is good
        uint256 rate = royaltyCurve(supply, cap, royalties[_did]);
        if (rate == 0) {
            return true;
        }

        // If (sum(_amounts) == 0) - It means there is no payment so everything is valid
        // returns true;
        uint256 _totalAmount = 0;
        for(uint i = 0; i < _amounts.length; i++)
            _totalAmount = _totalAmount + _amounts[i];
        // If the amount to receive by the creator is lower than royalties the calculation is not valid
        // return false;
        uint256 _requiredRoyalties = _totalAmount * rate / DENOMINATOR;

        if (_requiredRoyalties == 0)
            return true;
        
        // If (_did.creator is not in _receivers) - It means the original creator is not included as part of the payment
        // return false;
        address recipient = registry.getDIDRoyaltyRecipient(_did);
        bool found = false;
        uint256 index;
        for (index = 0; index < _receivers.length; index++) {
            if (recipient == _receivers[index])  {
                found = true;
                break;
            }
        }

        // The creator royalties are not part of the rewards
        if (!found) {
            return false;
        }

        // Check if royalties are enough
        // Are we paying enough royalties in the secondary market to the original creator?
        return (_amounts[index] >= _requiredRoyalties);
    }

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        if (address(registry) == address(0)) {
            return address(0);
        }
        return registry.getNvmConfigAddress();
    }
}

