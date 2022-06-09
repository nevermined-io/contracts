pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../libraries/HashListLibrary.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';


contract HashListLibraryProxy is OwnableUpgradeable {

    using HashListLibrary for HashListLibrary.List;        
    HashListLibrary.List private testData;

    function initialize(
        address _owner
    )
        public
        initializer
    {
        testData.setOwner(msg.sender);
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
    }

    
    function hash(
        address _address
    )
        public
        pure
        returns(bytes32)
    {
        return keccak256(abi.encode(_address));
    }
        
    function add(
        bytes32[] calldata values
    )
        external
        returns(bool)
    {
        return testData.add(values);
    }
    
    function add(
        bytes32 value
    )
        external
        returns(bool)
    {
        return testData.add(value);
    }
    
    function update(
        bytes32 oldValue,
        bytes32 newValue
    )
        external
        returns(bool)
    {
        return testData.update(oldValue, newValue);
    }
    
    function index(
        uint256 from,
        uint256 to
    )
        external
        returns(bool)
    {
        return testData.index(from, to);
    }
    
    function has(
        bytes32 value
    ) 
        external 
        view
        returns(bool)
    {
        return testData.has(value);
    }
    
    function remove(
        bytes32 value
    )
        external
        returns(bool)
    {
        return testData.remove(value);
    }
    
    
    function get(
        uint256 _index
    )
        external
        view
        returns(bytes32)
    {
        return testData.get(_index);
    }
    
    function size()
        external
        view
        returns(uint256)
    {
        return testData.size();
    }
    
    function all()
        external
        view
        returns(bytes32[] memory)
    {
        return testData.all();
    }
    
    function indexOf(
        bytes32 value
    )
        external
        view
        returns(uint256)
    {
        return testData.indexOf(value);
    }
    
    function ownedBy()
        external
        view
        returns(address)
    {
        return testData.ownedBy();
    }
    
    function isIndexed()
        external
        view
        returns(bool)
    {
        return testData.isIndexed();
    }
}
