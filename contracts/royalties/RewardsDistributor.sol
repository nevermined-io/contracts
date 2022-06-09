pragma solidity ^0.8.0;
// Copyright 2021 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '../registry/DIDRegistry.sol';
import '../conditions/ConditionStoreLibrary.sol';
import '../conditions/ConditionStoreManager.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

contract RewardsDistributor is Initializable {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Used condition ids
    mapping (bytes32 => bool) public used;
    mapping (bytes32 => address[]) public receivers;

    DIDRegistry public registry;
    ConditionStoreManager public conditionStoreManager;
    address public escrow;

    function initialize(address _registry, address _conditionStoreManager, address _escrow) public initializer {
        registry = DIDRegistry(_registry);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManager
        );
        escrow = _escrow;
    }

    /**
     * @notice set receivers for did
     * @param _did DID
     * @param _addr list of receivers
     */
    function setReceivers(bytes32 _did, address[] memory _addr) public {
        require(msg.sender == registry.getDIDCreator(_did), 'only creator can change');
        receivers[_did] = _addr;
    }

    /**
     * @notice distribute rewards associated with an escrow condition
     * @dev as paramemeters, it just gets the same parameters as fulfill for escrow condition
     * @param _agreementId agreement identifier
     * @param _did asset decentralized identifier          
     * @param _amounts token amounts to be locked/released
     * @param _receivers receiver's address
     * @param _lockPaymentAddress lock payment contract address
     * @param _tokenAddress the ERC20 contract address to use during the payment
     * @param _lockCondition lock condition identifier
     * @param _releaseConditions release condition identifier
     */
    function claimReward(
        bytes32 _agreementId,
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32[] memory _releaseConditions
    ) public {
        {
            bytes32 id = keccak256(abi.encode(_agreementId, escrow, keccak256(
                abi.encode(
                    _did,
                    _amounts,
                    _receivers,
                    _returnAddress,
                    _lockPaymentAddress, 
                    _tokenAddress,
                    _lockCondition,
                    _releaseConditions
                )))
            );
            require(conditionStoreManager.getConditionState(id) == ConditionStoreLibrary.ConditionState.Fulfilled, 'condition not fulfilled');
            require(!used[id], 'already claimed');
            used[id] = true;
        }
        uint256 rewardAmount = 0;
        for (uint256 i = 0; i < _receivers.length; i++) {
            if (_receivers[i] == address(this)) {
                rewardAmount += _amounts[i];
            }
        }
        uint256 receiversLen = receivers[_did].length;
        if (_tokenAddress == address(0)) {
            for (uint256 i = 0; i < receiversLen; i++) {
                if (i == 0) {
                    bool sent;
                    // solhint-disable-next-line                    
                    (sent,) = receivers[_did][i].call{value: rewardAmount - (rewardAmount / receiversLen) * (receiversLen-1)}('');
                } else {
                    bool sent;
                    // solhint-disable-next-line
                    (sent,) = receivers[_did][i].call{value: rewardAmount / receiversLen}('');
                }
            }
        } else {
            for (uint256 i = 0; i < receiversLen; i++) {
                if (i == 0) {
                    IERC20Upgradeable(_tokenAddress).safeTransfer(
                        receivers[_did][i],
                        rewardAmount - (rewardAmount / receiversLen) * (receiversLen-1)
                    );
                } else {
                    IERC20Upgradeable(_tokenAddress).safeTransfer(receivers[_did][i], rewardAmount / receiversLen);
                }
            }
        }
    }
}
