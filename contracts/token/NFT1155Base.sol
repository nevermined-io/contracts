// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../interfaces/IAsset.sol';
import {CREDITS_BURN_PROOF_TYPEHASH, INFT1155} from '../interfaces/INFT1155.sol';
import {AccessManagedUUPSUpgradeable} from '../proxy/AccessManagedUUPSUpgradeable.sol';
import {ERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import {EIP712Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol';

import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

import {CREDITS_BURNER_ROLE, CREDITS_MINTER_ROLE, CREDITS_TRANSFER_ROLE} from '../common/Roles.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

/**
 * @title NFT1155Base
 * @author Nevermined
 * @notice Abstract base contract for implementing ERC1155-based credit tokens in the Nevermined ecosystem
 * @dev This contract extends ERC1155Upgradeable to implement credit tokens with role-based permissions for minting,
 * burning, and transferring. It uses OpenZeppelin's AccessManagedUUPSUpgradeable for permissions management and
 * implements custom redemption rules based on plan configurations.
 *
 * Credits are linked to specific plans defined in the AssetsRegistry contract. Each plan has its own configuration
 * regarding how credits can be minted, redeemed, and by whom.
 *
 * This contract prevents credit transfers by default, as credits are designed to be non-transferable.
 */
abstract contract NFT1155Base is ERC1155Upgradeable, INFT1155, EIP712Upgradeable, AccessManagedUUPSUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("nevermined.nft1155base.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NFT1155_BASE_STORAGE_LOCATION =
        0x5dc28ad3de163acbf47a88082c92b50b1954ae8a6818aca0c0ef6cb317ac6500;

    /// @custom:storage-location erc7201:nevermined.nft1155base.storage
    struct NFT1155BaseStorage {
        IAsset assetsRegistry;
        mapping(address sender => mapping(uint256 keyspace => uint256 nonce)) nonces;
        mapping(address burner => mapping(uint256 planId => bool canBurn)) canBurn;
    }

    /**
     * @notice Initializes the NFT1155Base contract with required dependencies
     * @param _authority Address of the AccessManager contract
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract
     * @dev Internal initialization function to be called by inheriting contracts
     */
    // solhint-disable-next-line func-name-mixedcase
    function __NFT1155Base_init(IAccessManager _authority, IAsset _assetsRegistryAddress) internal onlyInitializing {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        require(_assetsRegistryAddress != IAsset(address(0)), InvalidAssetsRegistryAddress());
        require(_authority != IAccessManager(address(0)), InvalidAddress());

        __AccessManagedUUPSUpgradeable_init(address(_authority));
        __EIP712_init(type(NFT1155Base).name, '1');

        $.assetsRegistry = _assetsRegistryAddress;
    }

    /**
     * It gets the balance of multiple tokens for multiple owners.
     * @param _owners the array of owners address
     * @param _ids the array of token ids (planId)
     * @return the array of balances
     * @dev The length of the owners and ids arrays must be the same
     */
    function balanceOfBatch(address[] memory _owners, uint256[] memory _ids)
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        uint256 _length = _ids.length;
        if (_length != _owners.length) revert InvalidLength(_length, _owners.length);

        uint256[] memory _balances = new uint256[](_length);
        for (uint256 i = 0; i < _length; i++) {
            _balances[i] = balanceOf(_owners[i], _ids[i]);
        }
        return _balances;
    }

    /**
     * It mints credits for a plan.
     * @notice Only the owner of the plan or an account with the CREDITS_MINTER_ROLE can mint credits
     * @notice The payment plan must exists
     * @param _to the receiver of the credits
     * @param _planId the plan id
     * @param _amount the number of credits to mint
     * @param _data additional data to pass to the receiver
     */
    function mint(address _to, uint256 _planId, uint256 _amount, bytes memory _data) public virtual {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);
        if (plan.lastUpdated == 0) revert IAsset.PlanNotFound(_planId);

        // Only the owner of the plan or an account with the CREDITS_MINTER_ROLE can mint credits
        (bool hasRole,) = IAccessManager(authority()).hasRole(CREDITS_MINTER_ROLE, msg.sender);
        require(hasRole || plan.owner == msg.sender, InvalidRole(msg.sender, CREDITS_MINTER_ROLE));

        _mint(_to, _planId, _amount, _data);
    }

    /**
     * It mints credits in batch.
     * @notice Only the owner of the plan or an account with the CREDITS_MINTER_ROLE can mint credits
     * @notice The payment plan must exists
     * @param _to the receiver of the credits
     * @param _ids the plan ids
     * @param _values the number of credits to mint
     * @param _data additional data to pass to the receiver
     */
    function mintBatch(address _to, uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        public
        virtual
    {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        address sender = msg.sender;
        (bool hasRole,) = IAccessManager(authority()).hasRole(CREDITS_MINTER_ROLE, sender);

        for (uint256 i = 0; i < _ids.length; i++) {
            IAsset.Plan memory plan = $.assetsRegistry.getPlan(_ids[i]);
            if (plan.lastUpdated == 0) revert IAsset.PlanNotFound(_ids[i]);
            require(hasRole || plan.owner == sender, InvalidRole(sender, CREDITS_MINTER_ROLE));
        }

        _mintBatch(_to, _ids, _values, _data);
    }

    /**
     * It burns/redeem credits for a plan.
     * @notice The redemption rules depend on the plan.credits.redemptionType
     * @param _from The address of the account that is getting the credits burned
     * @param _planId the plan id
     * @param _amount the number of credits to burn/redeem
     * @param _keyspace the keyspace of the nonce
     * @param _signature the signature of the credits burn proof
     */
    function burn(address _from, uint256 _planId, uint256 _amount, uint256 _keyspace, bytes calldata _signature)
        public
        virtual
    {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);
        require(plan.lastUpdated != 0, IAsset.PlanNotFound(_planId));

        uint256 creditsToRedeem = _creditsToRedeem(
            plan.credits.isRedemptionAmountFixed, _amount, plan.credits.minAmount, plan.credits.maxAmount
        );

        require(
            _canRedeemCredits(_planId, plan.owner, plan.credits.redemptionType, msg.sender, creditsToRedeem),
            InvalidRedemptionPermission(_planId, plan.credits.redemptionType, msg.sender)
        );

        if (plan.credits.proofRequired) {
            uint256[] memory planIds = new uint256[](1);
            planIds[0] = _planId;

            CreditsBurnProofData memory proof =
                CreditsBurnProofData({keyspace: _keyspace, nonce: $.nonces[_from][_keyspace]++, planIds: planIds});

            bytes32 digest = hashCreditsBurnProof(proof);
            address signer = ECDSA.recover(digest, _signature);
            require(signer == _from, InvalidCreditsBurnProof(signer, _from));
        }

        _burn(_from, _planId, creditsToRedeem);
    }

    /**
     * It burns/redeem credits in batch.
     * @param _from the address of the account that is getting the credits burned
     * @param _ids the array of plan ids
     * @param _amounts the array of number of credits to burn/redeem
     * @param _keyspace the keyspace of the nonce
     * @param _signature the signature of the credits burn proof
     */
    function burnBatch(
        address _from,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        uint256 _keyspace,
        bytes calldata _signature
    ) public virtual restricted {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        uint256[] memory planIdsToVerify = new uint256[](_ids.length);
        uint256 counter;
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 planId = _ids[i];

            IAsset.Plan memory plan = $.assetsRegistry.getPlan(planId);

            _amounts[i] = _creditsToRedeem(
                plan.credits.isRedemptionAmountFixed, _amounts[i], plan.credits.minAmount, plan.credits.maxAmount
            );

            if (plan.credits.proofRequired) {
                planIdsToVerify[counter++] = planId;
            }
        }

        // Set the array length
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            mstore(planIdsToVerify, counter)
        }

        if (planIdsToVerify.length > 0) {
            CreditsBurnProofData memory proof = CreditsBurnProofData({
                keyspace: _keyspace, nonce: $.nonces[_from][_keyspace]++, planIds: planIdsToVerify
            });
            bytes32 digest = hashCreditsBurnProof(proof);
            address signer = ECDSA.recover(digest, _signature);
            require(signer == _from, InvalidCreditsBurnProof(signer, _from));
        }

        _burnBatch(_from, _ids, _amounts);
    }

    function allowBurn(address _burner, uint256 _planId) public virtual override {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);
        require(plan.owner == msg.sender, OnlyOwnerCanAllowBurn(msg.sender, _planId));

        $.canBurn[_burner][_planId] = true;

        emit BurnerAllowed(msg.sender, _burner, _planId);
    }

    function revokeBurn(address _burner, uint256 _planId) public virtual override {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();

        IAsset.Plan memory plan = $.assetsRegistry.getPlan(_planId);
        require(plan.owner == msg.sender, OnlyOwnerCanAllowBurn(msg.sender, _planId));

        $.canBurn[_burner][_planId] = false;

        emit BurnerRevoked(msg.sender, _burner, _planId);
    }

    /**
     * @notice Returns the next nonce for the given sender and keyspace
     * @param _sender The address of the account
     * @param _keyspaces The keyspaces for which to generate the nonce
     * @return nonces The next nonce values
     */
    function nextNonce(address _sender, uint256[] calldata _keyspaces)
        external
        view
        override
        returns (uint256[] memory nonces)
    {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();
        nonces = new uint256[](_keyspaces.length);
        for (uint256 i = 0; i < _keyspaces.length; i++) {
            nonces[i] = $.nonces[_sender][_keyspaces[i]];
        }
        return nonces;
    }

    function hashCreditsBurnProof(CreditsBurnProofData memory _proof) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CREDITS_BURN_PROOF_TYPEHASH,
                    _proof.keyspace,
                    _proof.nonce,
                    keccak256(abi.encodePacked(_proof.planIds))
                )
            )
        );
    }

    function canBurn(address _burner, uint256 _planId) public view virtual returns (bool) {
        NFT1155BaseStorage storage $ = _getNFT1155BaseStorage();
        return $.canBurn[_burner][_planId];
    }

    /**
     * It calculates the number of credits to redeem based on the plan and the credits type
     * @notice The credits to redeem depend on the plan.credits.creditsType
     * @param _isRedemptionAmountFixed indicates if the redemption amount is fixed
     * @param _amount the number of credits requested to redeem
     * @param _min the minimum number of credits to redeem configured in the plan
     * @param _max the maximum number of credits to redeem configured in the plan
     * @return the number of credits to redeem
     */
    function _creditsToRedeem(bool _isRedemptionAmountFixed, uint256 _amount, uint256 _min, uint256 _max)
        internal
        pure
        returns (uint256)
    {
        if (_isRedemptionAmountFixed) {
            return _min;
        } else {
            if (_amount < _min) return _min;
            else if (_amount > _max) return _max;
            else return _amount;
        }
        // if (_creditsType == IAsset.CreditsType.DYNAMIC) {
        //     if (_amount < _min) return _min;
        //     else if (_amount > _max) return _max;
        //     else return _amount;
        // } else if (_creditsType == IAsset.CreditsType.FIXED) {
        //     return _min;
        // } else if (_creditsType == IAsset.CreditsType.EXPIRABLE) {
        //     return 1;
        // }
        // revert IAsset.InvalidRedemptionAmount(_planId, _creditsType, _amount);
    }

    /**
     * @notice Internal function to check if an account can redeem credits for a plan
     * @notice Credits holders (aka subscribers) can always redeem their own credits
     * @param _planId Identifier of the plan
     * @param _owner Owner of the plan
     * @param _redemptionType Type of redemption allowed for the plan
     * @param _sender Address attempting to redeem credits
     * @param _amountToRedeem The amount of credits the sender is attempting to redeem
     * @return Boolean indicating whether the sender can redeem credits
     * @dev Checks redemption permissions based on the plan's redemption type
     */
    function _canRedeemCredits(
        uint256 _planId,
        address _owner,
        IAsset.RedemptionType _redemptionType,
        address _sender,
        uint256 _amountToRedeem
    ) internal view returns (bool) {
        bool isHolder = balanceOf(_sender, _planId) >= _amountToRedeem;

        if (isHolder) {
            return true;
        } else if (_redemptionType == IAsset.RedemptionType.ONLY_GLOBAL_ROLE) {
            (bool hasRole,) = IAccessManager(authority()).hasRole(CREDITS_BURNER_ROLE, _sender);
            return hasRole;
        } else if (_redemptionType == IAsset.RedemptionType.ONLY_OWNER) {
            return _sender == _owner;
        } else if (_redemptionType == IAsset.RedemptionType.ONLY_PLAN_ROLE) {
            return canBurn(_sender, _planId);
        } else if (_redemptionType == IAsset.RedemptionType.OWNER_OR_GLOBAL_ROLE) {
            (bool hasRole,) = IAccessManager(authority()).hasRole(CREDITS_BURNER_ROLE, _sender);
            return hasRole || _sender == _owner;
        }
        return false;
    }

    //@solhint-disable-next-line
    function safeTransferFrom(
        address,
        /*from*/
        address,
        /*to*/
        uint256,
        /*id*/
        uint256,
        /*value*/
        bytes memory /*data*/
    )
        public
        virtual
        override
    {
        revert InvalidRole(msg.sender, CREDITS_TRANSFER_ROLE);
    }

    //@solhint-disable-next-line
    function safeBatchTransferFrom(
        address,
        /*from*/
        address,
        /*to*/
        uint256[] memory,
        /*ids*/
        uint256[] memory,
        /*values*/
        bytes memory /*data*/
    )
        public
        virtual
        override
    {
        revert InvalidRole(msg.sender, CREDITS_TRANSFER_ROLE);
    }

    function _getNFT1155BaseStorage() internal pure returns (NFT1155BaseStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := NFT1155_BASE_STORAGE_LOCATION
        }
    }
}
