pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './interfaces/IList.sol';
import './libraries/HashListLibrary.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

/**
 * @title HashLists contract
 * @author Nevermined
 * @dev Hash lists contract is a sample list contract in which uses 
 *      HashListLibrary.sol in order to store, retrieve, remove, and 
 *      update bytes32 values in hash lists.
 *      This is a reference implementation for IList interface. It is 
 *      used for whitelisting condition. Any entity can have its own 
 *      implementation of the interface in which could be used for the
 *      same condition.
 */

contract HashLists is OwnableUpgradeable, IList {
    
    using HashListLibrary for HashListLibrary.List;        
    mapping(bytes32 => HashListLibrary.List) private lists;
    
    /**
     * @dev HashLists Initializer
     * @param _owner The owner of the hash list
     * Runs only upon contract creation.
     */
    function initialize(
        address _owner
    )
        public initializer
    {
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
    }
    
    /**
     * @dev hash ethereum accounts
     * @param account Ethereum address
     * @return bytes32 hash of the account
     */
    function hash(address account)
        public
        pure
        returns(bytes32)
    {
        return keccak256(abi.encode(account));
    }
    
    /**
     * @dev put an array of elements without indexing
     *      this meant to save gas in case of large arrays
     * @param values is an array of elements value
     * @return true if values are added successfully
     */
    function add(
        bytes32[] calldata values
    )
        external
        returns(bool)
    {
        bytes32 id = hash(msg.sender);
        if(lists[id].ownedBy() == address(0))
            lists[id].setOwner(msg.sender);
        return lists[id].add(values);
    }
    
    /**
     * @dev add indexes an element then adds it to a list
     * @param value is a bytes32 value
     * @return true if value is added successfully
     */
    function add(
        bytes32 value
    )
        external
        returns(bool)
    {
        bytes32 id = hash(msg.sender);
        if(lists[id].ownedBy() == address(0))
            lists[id].setOwner(msg.sender);
        return lists[id].add(value);
    }
    
    /**
     * @dev update the value with a new value and maintain indices
     * @param oldValue is an element value in a list
     * @param newValue new value
     * @return true if value is updated successfully
     */
    function update(
        bytes32 oldValue,
        bytes32 newValue
    )
        external
        returns(bool)
    {
        bytes32 id = hash(msg.sender);
        return lists[id].update(oldValue, newValue);
    }
    
    /**
     * @dev index is used to map each element value to its index on the list 
     * @param from index is where to 'from' indexing in the list
     * @param to index is where to stop indexing
     * @return true if the sub list is indexed
     */
    function index(
        uint256 from,
        uint256 to
    )
        external
        returns(bool)
    {
        bytes32 id = hash(msg.sender);
        return lists[id].index(from, to);
    }
    
    /**
     * @dev has checks whether a value is exist
     * @param id the list identifier (the hash of list owner's address)
     * @param value is element value in list
     * @return true if the value exists
     */
    function has(
        bytes32 id,
        bytes32 value
    ) 
        external 
        view
        override
        returns(bool)
    {
        return lists[id].has(value);
    }
    
    /**
     * @dev has checks whether a value is exist
     * @param value is element value in list
     * @return true if the value exists
     */
    function has(
        bytes32 value
    )
        external
        view
        override
        returns(bool)
    {
        bytes32 id = hash(msg.sender);
        return lists[id].has(value);
    }
    
    /**
     * @dev remove value from a list, updates indices, and list size 
     * @param value is an element value in a list
     * @return true if value is removed successfully
     */ 
    function remove(
        bytes32 value
    )
        external
        returns(bool)
    {
        bytes32 id = hash(msg.sender);
        return lists[id].remove(value);
    }
    
    /**
     * @dev has value by index 
     * @param id the list identifier (the hash of list owner's address)
     * @param _index is where is value is stored in the list
     * @return the value if exists
     */
    function get(
        bytes32 id,
        uint256 _index
    )
        external
        view
        returns(bytes32)
    {
        return lists[id].get(_index);
    }
    
    /**
     * @dev size gets the list size
     * @param id the list identifier (the hash of list owner's address)
     * @return total length of the list
     */
    function size(
        bytes32 id
    )
        external
        view
        returns(uint256)
    {
        return lists[id].size();
    }
    
    /**
     * @dev all returns all list elements
     * @param id the list identifier (the hash of list owner's address)
     * @return all list elements
     */
    function all(
        bytes32 id
    )
        external
        view
        returns(bytes32[] memory)
    {
        return lists[id].all();
    }
    
    /**
     * @dev indexOf gets the index of a value in a list
     * @param id the list identifier (the hash of list owner's address)
     * @param value is element value in list
     * @return value index in list
     */
    function indexOf(
        bytes32 id,
        bytes32 value
    )
        external
        view
        returns(uint256)
    {
        return lists[id].indexOf(value);
    }
    
    /**
     * @dev ownedBy gets the list owner
     * @param id the list identifier (the hash of list owner's address)
     * @return list owner
     */
    function ownedBy(
        bytes32 id
    )
        external
        view
        returns(address)
    {
        return lists[id].ownedBy();
    }
    
    /**
     * @dev isIndexed checks if the list is indexed
     * @param id the list identifier (the hash of list owner's address)
     * @return true if the list is indexed
     */
    function isIndexed(
        bytes32 id
    )
        external
        view
        returns(bool)
    {
        return lists[id].isIndexed();
    }
}
