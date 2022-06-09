pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';

/**
 * @title Hash List library
 * @author Nevermined
 * @dev Implementation of the basic functionality of list of hash values.
 * This library allows other contracts to build and maintain lists
 * and also preserves the privacy of the data by accepting only hashed 
 * content (bytes32 based data type)
 */

library HashListLibrary {
    
    using SafeMathUpgradeable for uint256;
    
    struct List {
        address _owner;
        bytes32[] values;
        mapping (bytes32 => uint256) indices;
    }
    
    modifier onlyListOwner(List storage _self)
    {
        require(
            _self._owner == msg.sender || _self._owner == address(0),
            'Invalid whitelist owner'
        );
        _;
    }
    
    /**
     * @dev add index an element then add it to a list
     * @param _self is a pointer to list in the storage
     * @param value is a bytes32 value
     * @return true if value is added successfully
     */
    function add(
        List storage _self,
        bytes32 value
    )
        public
        onlyListOwner(_self)
        returns(bool)
    {
        require(
            _self.indices[value] == 0,
            'Value already exists'
        );
        
        _self.values.push(value);
        _self.indices[value] = _self.values.length;
        return true;
    }
    
    /**
     * @dev put an array of elements without indexing
     *      this meant to save gas in case of large arrays
     * @param _self is a pointer to list in the storage
     * @param values is an array of elements value
     * @return true if values are added successfully
     */
    function add(
        List storage _self,
        bytes32[] memory values
    )
        public
        onlyListOwner(_self)
        returns(bool)
    {
        _self.values = values;
        return true;
    }
    
    /**
     * @dev update the value with a new value and maintain indices
     * @param _self is a pointer to list in the storage
     * @param oldValue is an element value in a list
     * @param newValue new value
     * @return true if value is updated successfully
     */
    function update(
        List storage _self,
        bytes32 oldValue,
        bytes32 newValue
    )
        public
        onlyListOwner(_self)
        returns(bool)
    {
        require(
            _self.indices[oldValue] != 0,
            'Value does not exist'
        );
        
        require(
            oldValue != newValue,
            'Value already exists'
        );
    
        uint256 oldValueIndex = _self.indices[oldValue];
        _self.values[oldValueIndex - 1] = newValue;
        _self.indices[newValue] = oldValueIndex;
        delete _self.indices[oldValue];
        return true;
    }
    
    /**
     * @dev remove value from a list, updates indices, and list size 
     * @param _self is a pointer to list in the storage
     * @param value is an element value in a list
     * @return true if value is removed successfully
     */ 
    function remove(
        List storage _self,
        bytes32 value
    )
        public
        onlyListOwner(_self)
        returns(bool)
    {
        require(
            _self.indices[value] > 0,
            'Failed to remove element from list'
        ); 
        uint256 valueIndex = _self.indices[value].sub(1);
        // copy the last element to this index
        _self.values[valueIndex] = _self.values[_self.values.length.sub(1)];
        // update the index of the last element to the new index
        bytes32 lastElementValue = _self.values[_self.values.length.sub(1)];
        _self.indices[lastElementValue] = _self.indices[value];
        // delete the last element
        delete _self.values[_self.values.length.sub(1)];
        // delete old value from indices
        delete _self.indices[value];
        return true;
    }
    
    /**
     * @dev has value by index 
     * @param _self is a pointer to list in the storage
     * @param __index is where is value is stored in the list
     * @return the value if exists
     */
    function get(
        List storage _self,
        uint256 __index
    )
        public
        view
        returns(bytes32)
    {
        require(
            __index > 0 &&
            __index <= _self.values.length,
            'Index is out of range'
        );
        return _self.values[__index - 1];
    }
    
    /**
     * @dev index is used to map each element value to its index on the list 
     * @param _self is a pointer to list in the storage
     * @param from index is where to 'from' indexing in the list
     * @param to index is where to stop indexing
     * @return true if the sub list is indexed
     */
    function index(
        List storage _self,
        uint256 from,
        uint256 to
    )
        public
        onlyListOwner(_self)
        returns(bool)
    {
        require(
            from > 0,
            'from index should be greater than zero'
        );
        
        require(
            from <= _self.values.length &&
            to <= _self.values.length,
            'Indices are out of range'
        );
        
        require(
            from <= to,
            'Invalid indices'
        );
        
        bytes32 lastIndexValue = _self.values[_self.values.length - 1];
        require(
            _self.indices[lastIndexValue] != _self.values.length,
            'List is already indexed'
        );
        
        bytes32 endIndexValue = _self.values[to - 1];
        require(
            _self.indices[endIndexValue] != to,
            'Values already are indexed, try different indices'
        );
        
        return _index(_self, from, to);
    }
    
    /**
     * @dev setOwner set list owner
     * param _owner owner address
     */
    function setOwner(
        List storage _self,
        address _owner
    )
        public
        onlyListOwner(_self)
    {
        _self._owner = _owner;
    }

    /**
     * @dev indexOf gets the index of a value in a list
     * @param _self is a pointer to list in the storage
     * @param value is element value in list
     * @return value index in list
     */
    function indexOf(
        List storage _self,
        bytes32 value 
    )
        public
        view
        returns(uint256)
    {
        require(
            _self.indices[value] != 0,
            'Value does not exist'
        );
        return _self.indices[value];
    }
    
    /**
     * @dev isIndexed checks if the list is indexed
     * @param _self is a pointer to list in the storage
     * @return true if the list is indexed
     */
    function isIndexed(
        List storage _self
    )
        public
        view
        returns(bool)
    {
        bytes32 lastIndexValue = _self.values[_self.values.length - 1];
        if(_self.indices[lastIndexValue] == _self.values.length)
            return true;
        return false;
    }
    
    /**
     * @dev all returns all list elements
     * @param _self is a pointer to list in the storage
     * @return all list elements
     */
    function all(
        List storage _self
    )
        public
        view
        returns(bytes32[] memory)
    {
        return _self.values;
    }
    
    /**
     * @dev size returns the list size
     * @param _self is a pointer to list in the storage
     * @param value is element value in list
     * @return true if the value exists
     */
    function has(
        List storage _self,
        bytes32 value
    )
        public
        view
        returns(bool)
    {
        if(_self.indices[value] > 0)
            return true;
        return false;
    }
    
    /**
     * @dev size gets the list size
     * @param _self is a pointer to list in the storage
     * @return total length of the list
     */
    function size(
        List storage _self
    )
        public
        view
        returns(uint256)
    {
        return _self.values.length;
    }
    
    /**
     * @dev ownedBy gets the list owner
     * @param _self is a pointer to list in the storage
     * @return list owner
     */
    function ownedBy(
        List storage _self
    )
        public
        view
        returns(address)
    {
        return _self._owner;
    }
    
    /**
     * @dev _index assign index to the list elements
     * @param _self is a pointer to list in the storage
     * @param from is the starting index id
     * @param to is the ending index id
     */
    function _index(
        List storage _self,
        uint256 from,
        uint256 to
    )
        private
        returns(bool)
    {
        for(uint256 i = from - 1; i < to; i++)
            _self.indices[_self.values[i]] = i + 1;
        return true;
    }
}
