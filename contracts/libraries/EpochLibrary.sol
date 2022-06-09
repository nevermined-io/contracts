pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';

/**
 * @title Epoch Library
 * @author Nevermined
 *
 * @dev Implementation of Epoch Library.
 *      For an arbitrary Epoch, this library manages the life
 *      cycle of an Epoch. Usually this library is used for 
 *      handling the time window between conditions in an agreement.
 *      For more information about Epoch checkout the below link
 *      https://github.com/oceanprotocol/OEPs/issues/119   
 *      TODO: update to the OEP link
 */
library EpochLibrary {

    using SafeMathUpgradeable for uint256;

    struct Epoch {
        uint256 timeLock;
        uint256 timeOut;
        uint256 blockNumber;
    }

    struct EpochList {
        mapping(bytes32 => Epoch) epochs;
        bytes32[] epochIds; // UNUSED
    }

   /**
    * @notice create creates new Epoch
    * @param _self is the Epoch storage pointer
    * @param _timeLock value in block count (can not fulfill before)
    * @param _timeOut value in block count (can not fulfill after)
    */
    function create(
        EpochList storage _self,
        bytes32 _id,
        uint256 _timeLock,
        uint256 _timeOut
    )
        internal
    {
        require(
            _self.epochs[_id].blockNumber == 0,
            'Id already exists'
        );

        require(
            _timeLock.add(block.number) >= block.number &&
            _timeOut.add(block.number) >= block.number,
            'Indicating integer overflow/underflow'
        );

        if (_timeOut > 0 && _timeLock > 0) {
            require(
                _timeLock < _timeOut,
                'Invalid time margin'
            );
        }

        _self.epochs[_id] = Epoch({
            timeLock : _timeLock,
            timeOut : _timeOut,
            blockNumber : block.number
        });

        // _self.epochIds.push(_id);

    }

   /**
    * @notice isTimedOut means you cannot fulfill after
    * @param _self is the Epoch storage pointer
    * @return true if the current block number is gt timeOut
    */
    function isTimedOut(
        EpochList storage _self,
        bytes32 _id
    )
        external
        view
        returns (bool)
    {
        if (_self.epochs[_id].timeOut == 0) {
            return false;
        }

        return (block.number > getEpochTimeOut(_self.epochs[_id]));
    }

   /**
    * @notice isTimeLocked means you cannot fulfill before
    * @param _self is the Epoch storage pointer
    * @return true if the current block number is gt timeLock
    */
    function isTimeLocked(
        EpochList storage _self,
        bytes32 _id
    )
        external
        view
        returns (bool)
    {
        return (block.number < getEpochTimeLock(_self.epochs[_id]));
    }

   /**
    * @notice getEpochTimeOut
    * @param _self is the Epoch storage pointer
    */
    function getEpochTimeOut(
        Epoch storage _self
    )
        public
        view
        returns (uint256)
    {
        return _self.timeOut.add(_self.blockNumber);
    }

    /**
    * @notice getEpochTimeLock
    * @param _self is the Epoch storage pointer
    */
    function getEpochTimeLock(
        Epoch storage _self
    )
        public
        view
        returns (uint256)
    {
        return _self.timeLock.add(_self.blockNumber);
    }
}
