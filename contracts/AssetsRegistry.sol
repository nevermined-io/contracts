// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from './interfaces/IAsset.sol';
import {IFeeController} from './interfaces/IFeeController.sol';
import {IHook} from './interfaces/IHook.sol';
import {IIdentityRegistry} from './interfaces/IIdentityRegistry.sol';
import {INVMConfig} from './interfaces/INVMConfig.sol';
import {AccessManagedUUPSUpgradeable} from './proxy/AccessManagedUUPSUpgradeable.sol';
import {
    ERC721URIStorageUpgradeable
} from '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';
import {ERC165Checker} from '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/**
 * @title AssetsRegistry
 * @author Nevermined AG
 * @notice This contract manages the registration and lifecycle of digital assets in the Nevermined ecosystem.
 * @notice The registry is compliant with the ERC-8004 Identity Registry standard.
 * @dev The contract implements an upgradable pattern using ERC-7201 namespaced storage
 *      and OpenZeppelin's AccessManagedUUPSUpgradeable for access control.
 *      Assets are identified by unique DIDs (Decentralized Identifiers - aka agentId's) and can have
 *      multiple pricing plans associated with them.
 */
contract AssetsRegistry is IAsset, IIdentityRegistry, ERC721URIStorageUpgradeable, AccessManagedUUPSUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("nevermined.assetsregistry.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSETS_REGISTRY_STORAGE_LOCATION =
        0x6c9566430157c5ec4491fdbbed7bf67f82d06a6dee70d9aaa3ede461d7d98900;

    /// @custom:storage-location erc7201:nevermined.assetsregistry.storage
    struct AssetsRegistryStorage {
        /// @notice Configuration contract that stores system-wide parameters
        INVMConfig nvmConfig;
        /// @notice Mapping from asset DIDs to their metadata and associated information
        mapping(uint256 => DIDAgent) assets;
        /// @notice The mapping of the plans registered in the contract
        mapping(uint256 => Plan) plans;
        /// @notice Mapping of plan ID to array of hook contracts
        mapping(uint256 => IHook[]) planHooks;
        /// @notice Optional metadata per asset tokenId => key => value
        mapping(uint256 => mapping(string => bytes)) tokenMetadata;
        /// @notice Metadata keys per tokenId to enable enumeration
        mapping(uint256 => string[]) tokenMetadataKeys;
        /// @notice Tracks if a metadata key already exists for a tokenId
        mapping(uint256 => mapping(string => bool)) tokenMetadataKeyExists;
        /// @notice Counter of total minted asset NFTs (agents)
        uint256 totalAgents;
    }

    /**
     * @notice Initializes the AssetsRegistry contract with a configuration address and access manager
     * @param _nvmConfigAddress Address of the NVMConfig contract managing system configuration
     * @param _authority Address of the AccessManager contract handling permissions
     * @dev This function replaces the constructor for upgradeable contracts
     */
    function initialize(INVMConfig _nvmConfigAddress, IAccessManager _authority) external initializer {
        require(_nvmConfigAddress != INVMConfig(address(0)), INVMConfig.InvalidAddress(address(0)));
        require(_authority != IAccessManager(address(0)), INVMConfig.InvalidAddress(address(0)));
        _getAssetsRegistryStorage().nvmConfig = _nvmConfigAddress;
        __ERC721_init('Nevermined ERC-8004 Identity Registry', 'NVM-ASSET');
        __ERC721URIStorage_init();
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @dev Disable transfers by reverting on any transfer attempts (except mint/burn).
     */
    function _update(address _to, uint256 _tokenId, address _auth) internal override returns (address) {
        // Allow mint (from == address(0)) and burn (to == address(0)) via super._update() semantics in OZ v5
        // In OZ v5, _update returns previous owner and uses existence checks; we block if both from and to are non-zero
        address from = _ownerOf(_tokenId);
        if (from != address(0) && _to != address(0)) require(false, TransfersDisabled());
        return super._update(_to, _tokenId, _auth);
    }

    /**
     * @notice Retrieves an asset by its unique identifier (agent ID)
     * @param _agentId The unique identifier of the asset to retrieve
     * @return The DIDAgent structure containing the asset's metadata
     * @dev Returns an empty structure if the asset does not exist
     */
    function getAgent(uint256 _agentId) external view returns (DIDAgent memory) {
        return _getAssetsRegistryStorage().assets[_agentId];
    }

    /**
     * @notice Generates a agent id using as seed a bytes32 and the address of the DID creator
     * @param _seed refers to agent id Seed used as base to generate the final agent id
     * @param _creator address of the creator of the agent id
     * @return uint256 The new agent id created
     * @dev The agent id is deterministically generated by hashing the seed and creator address
     */
    function hashAgentId(bytes32 _seed, address _creator) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(_seed, _creator)));
    }

    /**
     * @notice Registers a new agent with associated plans
     * @param _seed Seed used to generate the final agent id
     * @param _url URL to the asset's metadata
     * @param _plans Array of plan IDs associated with the asset
     * @dev The agent id is generated by hashing the seed and creator address
     * @dev Emits AgentRegistered event on successful registration
     * @dev Allows the registration of assets without any plan, with the intention of further addition
     * @dev Will revert if the agent id already exists or any plan doesn't exist
     */
    function register(bytes32 _seed, string memory _url, uint256[] memory _plans) public virtual returns (uint256) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if (bytes(_url).length == 0) {
            revert InvalidURL(_url);
        }

        uint256 agentId = hashAgentId(_seed, msg.sender);
        if ($.assets[agentId].owner != address(0x0)) {
            revert AgentAlreadyRegistered(agentId);
        }

        for (uint256 i = 0; i < _plans.length; i++) {
            if ($.plans[_plans[i]].lastUpdated == 0) {
                revert PlanNotFound(_plans[i]);
            }
        }
        $.assets[agentId] =
            DIDAgent({owner: msg.sender, creator: msg.sender, url: _url, lastUpdated: block.timestamp, plans: _plans});

        emit AgentRegistered(agentId, msg.sender);

        // Mint a non-transferable ERC721 for this asset using agentId as tokenId
        _mint(msg.sender, agentId);
        _setTokenURI(agentId, _url);
        $.totalAgents++;

        return agentId;
    }

    /**
     * @notice Register an Agent and mint the asset NFT with tokenURI and optional metadata
     * @param _seed Seed used to derive the tokenId and agent
     * @param _tokenURI The metadata URI for the asset NFT
     * @param _plans Array of plan IDs associated with the asset
     * @param _metadata Optional metadata entries to attach on-chain to the asset NFT
     */
    function register(
        bytes32 _seed,
        string memory _tokenURI,
        uint256[] memory _plans,
        IIdentityRegistry.MetadataEntry[] memory _metadata
    ) public {
        uint256 agentId = register(_seed, _tokenURI, _plans);
        // Store optional metadata
        for (uint256 i = 0; i < _metadata.length; i++) {
            _setTokenMetadata(agentId, _metadata[i].key, _metadata[i].value);
        }
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function register(string memory tokenURI, IIdentityRegistry.MetadataEntry[] memory metadata)
        public
        override
        returns (uint256 agentId)
    {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        // Generate unique agentId using hash of sender, timestamp, and totalAgents counter
        agentId = uint256(keccak256(abi.encode(msg.sender, block.timestamp, $.totalAgents)));

        // Ensure uniqueness (unlikely but possible)
        uint256 attempts = 0;
        while (_ownerOf(agentId) != address(0) && attempts < 10) {
            agentId = uint256(keccak256(abi.encode(agentId, block.timestamp, attempts)));
            attempts++;
        }

        require(_ownerOf(agentId) == address(0), AgentAlreadyRegistered(agentId));

        _mint(msg.sender, agentId);
        if (bytes(tokenURI).length > 0) {
            _setTokenURI(agentId, tokenURI);
        }

        // Set metadata entries
        for (uint256 i = 0; i < metadata.length; i++) {
            _setTokenMetadata(agentId, metadata[i].key, metadata[i].value);
            emit MetadataSet(agentId, metadata[i].key, metadata[i].key, metadata[i].value);
        }

        $.totalAgents++;

        emit Registered(agentId, tokenURI, msg.sender);
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function register(string calldata tokenURI) external override returns (uint256 agentId) {
        IIdentityRegistry.MetadataEntry[] memory emptyMetadata = new IIdentityRegistry.MetadataEntry[](0);
        return register(tokenURI, emptyMetadata);
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function register() external override returns (uint256 agentId) {
        return register('', new IIdentityRegistry.MetadataEntry[](0));
    }

    function _createEmptyPlan() internal returns (uint256 planId) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();
        planId = uint256(keccak256(abi.encode('EMPTY_PLAN', msg.sender, block.number)));
        if ($.plans[planId].lastUpdated != 0) return planId;
        $.plans[planId] = Plan({
            owner: msg.sender,
            price: PriceConfig(
                false,
                address(0),
                new uint256[](0),
                new address[](0),
                address(0),
                IFeeController(address(0)),
                address(0)
            ),
            credits: CreditsConfig(false, RedemptionType.ONLY_OWNER, false, 0, 0, 0, 0, address(0)),
            lastUpdated: block.timestamp
        });
        emit PlanRegistered(planId, msg.sender);
    }

    function _setTokenMetadata(uint256 tokenId, string memory key, bytes memory value) internal {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();
        if (!$.tokenMetadataKeyExists[tokenId][key]) {
            $.tokenMetadataKeys[tokenId].push(key);
            $.tokenMetadataKeyExists[tokenId][key] = true;
        }
        $.tokenMetadata[tokenId][key] = value;
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function getMetadata(uint256 agentId, string calldata key) public view override returns (bytes memory value) {
        return _getAssetsRegistryStorage().tokenMetadata[agentId][key];
    }

    function getMetadataKeys(uint256 agentId) public view returns (string[] memory keys) {
        return _getAssetsRegistryStorage().tokenMetadataKeys[agentId];
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function getTotalAgents() public view override returns (uint256 count) {
        return _getAssetsRegistryStorage().totalAgents;
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function agentExists(uint256 agentId) public view override returns (bool exists) {
        return _ownerOf(agentId) != address(0);
    }

    /**
     * @inheritdoc IIdentityRegistry
     */
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) public override restricted {
        require(_isAuthorized(_ownerOf(agentId), msg.sender, agentId), NotAuthorized());
        _setTokenMetadata(agentId, key, value);
        emit MetadataSet(agentId, key, key, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorageUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IIdentityRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IIdentityRegistry
     * @dev Reverts because agent IDs are hash-based and cannot be predicted
     */
    function getNextAgentId() external pure override returns (uint256) {
        revert IIdentityRegistry.AgentIdsAreHashBased();
    }

    /**
     * @notice Creates a new pricing plan with specified configuration
     * @param _priceConfig Configuration for the plan's pricing model
     * @param _creditsConfig Configuration for the credits granted by the plan
     * @param _hooks Array of hook contracts to be called during agreement creation
     * @param _nonce Optional nonce to ensure unique plan IDs when using identical configurations
     * @return planId The ID of the created plan
     * @dev The nonce allows creating multiple plans with the same parameters but different identifiers
     * @dev Will revert if the NFT address is invalid or Nevermined fees aren't properly included for fixed price plans
     */
    function _createPlan(
        PriceConfig memory _priceConfig,
        CreditsConfig memory _creditsConfig,
        IHook[] memory _hooks,
        uint256 _nonce
    ) internal returns (uint256) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if (_creditsConfig.minAmount > _creditsConfig.maxAmount) {
            revert InvalidCreditsConfigAmounts(_creditsConfig.minAmount, _creditsConfig.maxAmount);
        }

        if (_priceConfig.amounts.length != _priceConfig.receivers.length) {
            revert PriceConfigInvalidAmountsOrReceivers();
        }

        uint256 planId = hashPlanId(_priceConfig, _creditsConfig, msg.sender, _nonce);
        if ($.plans[planId].lastUpdated != 0) {
            revert PlanAlreadyRegistered(planId);
        }

        if (
            _priceConfig.feeController != $.nvmConfig.getDefaultFeeController()
                && _priceConfig.feeController != IFeeController(address(0x0))
        ) {
            require(
                $.nvmConfig.isFeeControllerAllowed(_priceConfig.feeController, msg.sender),
                NotAllowedToSetFeeController(msg.sender, _priceConfig.feeController)
            );
        }

        if (!_isNFT1155Contract(_creditsConfig.nftAddress)) {
            revert InvalidNFTAddress(_creditsConfig.nftAddress);
        }

        // Create the plan first
        $.plans[planId] =
            Plan({owner: msg.sender, price: _priceConfig, credits: _creditsConfig, lastUpdated: block.timestamp});

        // If the price type is FIXED_PRICE, we need to check if the Nevermined fees are included in the payment distribution
        if (!areNeverminedFeesIncluded(planId)) {
            revert NeverminedFeesNotIncluded(_priceConfig.amounts, _priceConfig.receivers);
        }

        // Store hooks for this plan
        uint256 previousHook = 0;
        for (uint256 i = 0; i < _hooks.length; i++) {
            uint256 hookId = uint256(uint160(address(_hooks[i])));
            require(hookId > previousHook, HooksMustBeUnique());
            previousHook = hookId;

            $.planHooks[planId].push(_hooks[i]);
        }

        emit PlanRegistered(planId, msg.sender);
        return planId;
    }

    /**
     * @notice Creates a new pricing plan with specified configuration
     * @param _priceConfig Configuration for the plan's pricing model
     * @param _creditsConfig Configuration for the credits granted by the plan
     * @param _hooks Array of hook contracts to be called during agreement creation
     * @param _nonce Optional nonce to ensure unique plan IDs
     * @return planId The ID of the created plan
     */
    function createPlanWithHooks(
        PriceConfig memory _priceConfig,
        CreditsConfig memory _creditsConfig,
        IHook[] calldata _hooks,
        uint256 _nonce
    ) public returns (uint256) {
        IHook[] memory hooks = _hooks;
        return _createPlan(_priceConfig, _creditsConfig, hooks, _nonce);
    }

    /**
     * @notice Creates a new pricing plan with specified configuration and nonce
     * @param _priceConfig Configuration for the plan's pricing model
     * @param _creditsConfig Configuration for the credits granted by the plan
     * @param _nonce Optional nonce to ensure unique plan IDs
     * @return planId The ID of the created plan
     * @dev Uses no hooks
     */
    function createPlan(PriceConfig memory _priceConfig, CreditsConfig memory _creditsConfig, uint256 _nonce)
        public
        returns (uint256)
    {
        IHook[] memory emptyHooks = new IHook[](0);
        return _createPlan(_priceConfig, _creditsConfig, emptyHooks, _nonce);
    }

    /**
     * @notice Registers a new asset and creates an associated pricing plan in a single transaction
     * @param _seed Seed used to generate the final agent ID
     * @param _url URL to the asset's metadata
     * @param _priceConfig Configuration for the plan's pricing model
     * @param _creditsConfig Configuration for the credits granted by the plan
     * @dev If the plan already exists, it will be reused rather than recreated
     * @dev This is a convenience function that combines plan creation and asset registration
     */
    function registerAgentAndPlan(
        bytes32 _seed,
        string memory _url,
        PriceConfig memory _priceConfig,
        CreditsConfig memory _creditsConfig
    ) external {
        uint256 planId = hashPlanId(_priceConfig, _creditsConfig, msg.sender);
        if (!planExists(planId)) {
            IHook[] memory emptyHooks = new IHook[](0);
            _createPlan(_priceConfig, _creditsConfig, emptyHooks, 0);
        }

        uint256[] memory _assetPlans = new uint256[](1);
        _assetPlans[0] = planId;
        register(_seed, _url, _assetPlans);
    }

    /**
     * @notice Retrieves a plan by its unique identifier
     * @param _planId The unique identifier of the plan to retrieve
     * @return The Plan structure containing the plan's configuration
     * @dev Returns an empty structure if the plan does not exist
     */
    function getPlan(uint256 _planId) external view returns (Plan memory) {
        return _getAssetsRegistryStorage().plans[_planId];
    }

    /**
     * @notice Checks if a plan exists by its unique identifier
     * @param _planId The unique identifier of the plan to check
     * @return Boolean indicating whether the plan exists
     * @dev A plan exists if it has been registered and has a non-zero lastUpdated timestamp
     */
    function planExists(uint256 _planId) public view returns (bool) {
        return _getAssetsRegistryStorage().plans[_planId].lastUpdated != 0;
    }

    /**
     * @notice Checks if the has associated a specific template address
     * @param _planId The unique identifier of the plan to check
     * @param _templateAddress The address of the template to check
     * @return Boolean indicating whether the plan exists
     * @dev A plan has a specific template address
     */
    function isPlanTemplate(uint256 _planId, address _templateAddress) public view returns (bool) {
        return _getAssetsRegistryStorage().plans[_planId].price.templateAddress == _templateAddress;
    }

    /**
     * @notice Internal function to check if an address is the owner of a plan
     * @param _planId The ID of the plan to check
     * @param _address The address to check
     * @return bool True if the address is the plan owner
     */
    function _isPlanOwner(uint256 _planId, address _address) internal view returns (bool) {
        return _getAssetsRegistryStorage().plans[_planId].owner == _address;
    }

    /**
     * @notice Given the plan attributes and the address of the plan creator, it computes a unique identifier for the plan
     * @param _priceConfig The price configuration of the plan
     * @param _creditsConfig The credits configuration of the plan
     * @param _creator The address of the user that created the plan
     * @param _nonce Optional nonce to ensure uniqueness of the plan ID
     * @return uint256 The unique identifier of the plan
     * @dev The ID is deterministically generated by hashing all plan parameters together
     */
    function hashPlanId(
        PriceConfig memory _priceConfig,
        CreditsConfig memory _creditsConfig,
        address _creator,
        uint256 _nonce
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(_priceConfig, _creditsConfig, _creator, _nonce)));
    }

    /**
     * @notice Given the plan attributes and the address of the plan creator, it computes a unique identifier for the plan
     * @param _priceConfig The price configuration of the plan
     * @param _creditsConfig The credits configuration of the plan
     * @param _creator The address of the user that created the plan
     * @return uint256 The unique identifier of the plan
     * @dev Convenience overload that uses a default nonce of 0
     */
    function hashPlanId(PriceConfig memory _priceConfig, CreditsConfig memory _creditsConfig, address _creator)
        public
        pure
        returns (uint256)
    {
        return hashPlanId(_priceConfig, _creditsConfig, _creator, 0);
    }

    /**
     * @notice Add a new plan to an agent. This can only be done by the agent owner.
     * @param _agentId The unique identifier of the agent
     * @param _planId The unique identifier of the plan to add
     * @dev If the plan is already associated with the agent, the function returns without making changes
     * @dev Emits PlanAddedToAgent event on successful addition
     */
    function addPlanToAgent(uint256 _agentId, uint256 _planId) external {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.assets[_agentId].lastUpdated == 0) {
            revert AgentNotFound(_agentId);
        }

        if ($.assets[_agentId].owner != msg.sender) {
            revert NotOwner(_agentId, msg.sender, $.assets[_agentId].owner);
        }

        if ($.plans[_planId].lastUpdated == 0) {
            revert PlanNotFound(_planId);
        }

        // Check if plan is already in the asset's plans array
        uint256[] memory currentPlans = $.assets[_agentId].plans;
        for (uint256 i = 0; i < currentPlans.length; i++) {
            if (currentPlans[i] == _planId) {
                // Plan is already in the list, nothing to do
                return;
            }
        }

        // Add plan to the asset's plans array
        $.assets[_agentId].plans.push(_planId);
        $.assets[_agentId].lastUpdated = block.timestamp;

        emit IAsset.PlanAddedToAgent(_agentId, _planId, msg.sender);
    }

    /**
     * @notice Remove a plan from an agent. This can only be done by the agent owner.
     * @param _agentId The unique identifier of the agent
     * @param _planId The unique identifier of the plan to remove
     * @dev Uses a gas-efficient swap-and-pop pattern for array removal
     * @dev Emits PlanRemovedFromAgent event on successful removal
     */
    function removePlanFromAgent(uint256 _agentId, uint256 _planId) external {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.assets[_agentId].lastUpdated == 0) {
            revert AgentNotFound(_agentId);
        }

        if ($.assets[_agentId].owner != msg.sender) {
            revert IAsset.NotOwner(_agentId, msg.sender, $.assets[_agentId].owner);
        }

        uint256[] storage plans = $.assets[_agentId].plans;
        bool found = false;
        uint256 indexToRemove;

        // Find the index of the plan to remove
        for (uint256 i = 0; i < plans.length; i++) {
            if (plans[i] == _planId) {
                found = true;
                indexToRemove = i;
                break;
            }
        }

        if (!found) {
            revert PlanNotInAgent(_agentId, _planId);
        }

        // Remove the plan by swapping with the last element and popping
        if (indexToRemove != plans.length - 1) {
            plans[indexToRemove] = plans[plans.length - 1];
        }
        plans.pop();

        // Update the lastUpdated timestamp
        $.assets[_agentId].lastUpdated = block.timestamp;

        emit IAsset.PlanRemovedFromAgent(_agentId, _planId, msg.sender);
    }

    /**
     * @notice Replace all plans for an agent with a new set of plans. This can only be done by the agent owner.
     * @param _agentId The unique identifier of the agent
     * @param _plans The new array of plan IDs to associate with the agent
     * @dev Validates that all new plans exist before replacing
     * @dev Emits AgentPlansReplaced event on successful replacement
     */
    function replacePlansForAgent(uint256 _agentId, uint256[] memory _plans) external {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.assets[_agentId].lastUpdated == 0) {
            revert AgentNotFound(_agentId);
        }

        if ($.assets[_agentId].owner != msg.sender) {
            revert NotOwner(_agentId, msg.sender, $.assets[_agentId].owner);
        }

        // Validate that all plans exist
        uint256 previousPlan = 0;
        for (uint256 i = 0; i < _plans.length; i++) {
            require(_plans[i] > previousPlan, PlansMustBeUnique());
            previousPlan = _plans[i];

            if ($.plans[_plans[i]].lastUpdated == 0) {
                revert PlanNotFound(_plans[i]);
            }
        }

        // Replace the plans
        $.assets[_agentId].plans = _plans;
        $.assets[_agentId].lastUpdated = block.timestamp;

        emit IAsset.AgentPlansReplaced(_agentId, msg.sender);
    }

    /**
     * @notice Transfers the ownership of an asset to a new owner
     * @param _agentId The identifier of the asset
     * @param _newOwner The address of the new owner
     * @dev Only the current owner can transfer ownership
     * @dev Emits AgentOwnershipTransferred event on successful transfer
     */
    function transferAgentOwnership(uint256 _agentId, address _newOwner) external {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.assets[_agentId].lastUpdated == 0) {
            revert AgentNotFound(_agentId);
        }

        if ($.assets[_agentId].owner != msg.sender) {
            revert NotOwner(_agentId, msg.sender, $.assets[_agentId].owner);
        }

        address previousOwner = $.assets[_agentId].owner;
        $.assets[_agentId].owner = _newOwner;
        $.assets[_agentId].lastUpdated = block.timestamp;

        emit AgentOwnershipTransferred(_agentId, previousOwner, _newOwner);
    }

    /**
     * @notice Transfers the ownership of a plan to a new owner
     * @param _planId The identifier of the plan
     * @param _newOwner The address of the new owner
     * @dev Only the current owner can transfer ownership
     * @dev Emits PlanOwnershipTransferred event on successful transfer
     */
    function transferPlanOwnership(uint256 _planId, address _newOwner) external {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.plans[_planId].lastUpdated == 0) {
            revert PlanNotFound(_planId);
        }

        if ($.plans[_planId].owner != msg.sender) {
            revert NotOwner(_planId, msg.sender, $.plans[_planId].owner);
        }

        address previousOwner = $.plans[_planId].owner;
        $.plans[_planId].owner = _newOwner;
        $.plans[_planId].lastUpdated = block.timestamp;

        emit PlanOwnershipTransferred(_planId, previousOwner, _newOwner);
    }

    /**
     * @notice Checks if Nevermined fees are included in the payment distribution
     * @param _planId The ID of the plan to check
     * @return bool True if Nevermined fees are properly included
     */
    function areNeverminedFeesIncluded(uint256 _planId) public view returns (bool) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();
        IAsset.Plan storage plan = $.plans[_planId];
        PriceConfig storage priceConfig = plan.price;
        address feeReceiver = $.nvmConfig.getFeeReceiver();

        if (feeReceiver == address(0)) return true;

        bool _feeReceiverIncluded = false;
        uint256 _feeReceiverIncludedAmount = 0;
        uint256 totalAmount = 0;
        uint256 amountsLength = priceConfig.amounts.length;
        for (uint256 i; i < amountsLength; i++) {
            if (priceConfig.receivers[i] == feeReceiver) {
                _feeReceiverIncluded = true;
                _feeReceiverIncludedAmount = priceConfig.amounts[i];
            }
            totalAmount += priceConfig.amounts[i];
        }

        if (totalAmount == 0) return true;

        // Calculate expected fee amount using the appropriate fee controller
        IFeeController feeController = plan.price.feeController == IFeeController(address(0))
            ? $.nvmConfig.getDefaultFeeController()
            : plan.price.feeController;
        (uint256 expectedFeeAmount,,) = feeController.calculateFee(totalAmount, plan.price, plan.credits);

        if (expectedFeeAmount == 0) return true;
        if (!_feeReceiverIncluded) return false;

        // Return if fee calculation is correct
        return expectedFeeAmount == _feeReceiverIncludedAmount;
    }

    /**
     * @notice Adds Nevermined fees to the payment distribution if not already included
     * @param priceConfig The price configuration of the plan
     * @param creditsConfig The credits configuration of the plan
     * @return amounts Updated array of payment amounts including fees
     * @return receivers Updated array of payment receivers including fee recipient
     */
    function addFeesToPaymentsDistribution(
        IAsset.PriceConfig calldata priceConfig,
        IAsset.CreditsConfig calldata creditsConfig
    ) external view returns (uint256[] memory amounts, address[] memory receivers) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.nvmConfig.getFeeReceiver() == address(0)) {
            return (priceConfig.amounts, priceConfig.receivers);
        }

        uint256 totalAmount = 0;
        uint256 amountsLength = priceConfig.amounts.length;
        for (uint256 i; i < amountsLength; i++) {
            totalAmount += priceConfig.amounts[i];
        }
        if (totalAmount == 0) return (priceConfig.amounts, priceConfig.receivers);

        // Calculate fee amount using the appropriate fee controller
        uint256 feeAmount;
        {
            IFeeController feeController = priceConfig.feeController == IFeeController(address(0))
                ? $.nvmConfig.getDefaultFeeController()
                : priceConfig.feeController;
            (feeAmount,,) = feeController.calculateFee(totalAmount, priceConfig, creditsConfig);
        }
        if (feeAmount == 0) return (priceConfig.amounts, priceConfig.receivers);

        uint256[] memory amountsWithFees = new uint256[](amountsLength + 1);
        for (uint256 i; i < amountsLength; i++) {
            amountsWithFees[i] = priceConfig.amounts[i];
        }
        amountsWithFees[amountsLength] = feeAmount;

        address[] memory receiversWithFees = new address[](amountsLength + 1);
        for (uint256 i; i < amountsLength; i++) {
            receiversWithFees[i] = priceConfig.receivers[i];
        }
        receiversWithFees[amountsLength] = $.nvmConfig.getFeeReceiver();

        return (amountsWithFees, receiversWithFees);
    }

    /**
     * @notice Getting a payment distribution, it includes the Nevermined fees if not already included
     * This method subsctracts the fees from the original amounts and adds a new entry for the fee recipient
     * @param priceConfig The price configuration of the plan
     * @param creditsConfig The credits configuration of the plan
     * @return amounts Updated array of payment amounts including fees
     * @return receivers Updated array of payment receivers including fee recipient
     */
    function includeFeesInPaymentsDistribution(
        IAsset.PriceConfig calldata priceConfig,
        IAsset.CreditsConfig calldata creditsConfig
    ) external view returns (uint256[] memory amounts, address[] memory receivers) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.nvmConfig.getFeeReceiver() == address(0)) {
            return (priceConfig.amounts, priceConfig.receivers);
        }

        uint256 totalAmount = 0;
        uint256 amountsLength = priceConfig.amounts.length;
        for (uint256 i; i < amountsLength; i++) {
            totalAmount += priceConfig.amounts[i];
        }
        if (totalAmount == 0) return (priceConfig.amounts, priceConfig.receivers);

        // Calculate fee amount using the appropriate fee controller
        uint256 feeAmount;
        uint256 feeRate;
        uint256 feeDenominator;
        {
            IFeeController feeController = priceConfig.feeController == IFeeController(address(0))
                ? $.nvmConfig.getDefaultFeeController()
                : priceConfig.feeController;
            (feeAmount, feeRate, feeDenominator) = feeController.calculateFee(totalAmount, priceConfig, creditsConfig);
        }
        if (feeAmount == 0) return (priceConfig.amounts, priceConfig.receivers);

        uint256[] memory amountsWithFees = new uint256[](amountsLength + 1);
        for (uint256 i; i < amountsLength; i++) {
            amountsWithFees[i] = priceConfig.amounts[i] - ((priceConfig.amounts[i] * feeRate) / feeDenominator);
        }
        amountsWithFees[amountsLength] = feeAmount;

        address[] memory receiversWithFees = new address[](amountsLength + 1);
        for (uint256 i; i < amountsLength; i++) {
            receiversWithFees[i] = priceConfig.receivers[i];
        }
        receiversWithFees[amountsLength] = $.nvmConfig.getFeeReceiver();

        return (amountsWithFees, receiversWithFees);
    }

    /**
     * @notice Checks if an address is a valid ERC-1155 NFT contract
     * @param _nftAddress The address to check
     * @return bool True if the address contains code and implements ERC-1155
     * @dev Uses the ERC-165 interface detection standard to check for ERC-1155 support
     */
    function _isNFT1155Contract(address _nftAddress) internal view returns (bool) {
        return ERC165Checker.supportsInterface(_nftAddress, 0xd9b67a26);
    }

    /**
     * @notice Accesses the contract's namespaced storage slot using ERC-7201
     * @return $ Reference to the contract's storage struct
     * @dev Uses assembly to access the specific storage slot for this contract's data
     */
    function _getAssetsRegistryStorage() internal pure returns (AssetsRegistryStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := ASSETS_REGISTRY_STORAGE_LOCATION
        }
    }

    /**
     * @notice Gets the hooks associated with a plan
     * @param _planId The ID of the plan
     * @return Array of hook contracts
     */
    function getPlanHooks(uint256 _planId) external view returns (IHook[] memory) {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();
        return $.planHooks[_planId];
    }

    /**
     * @notice Sets the hooks for a plan
     * @param _planId The ID of the plan
     * @param _hooks Array of hook contracts
     * @dev Only callable by the plan owner or authorized roles
     */
    function setPlanHooks(uint256 _planId, IHook[] calldata _hooks) external {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        // Verify plan exists and caller has permission
        if (!planExists(_planId)) revert PlanNotFound(_planId);
        if (!_isPlanOwner(_planId, msg.sender)) {
            revert NotOwner(_planId, msg.sender, $.plans[_planId].owner);
        }

        // Clear existing hooks
        delete $.planHooks[_planId];

        // Set new hooks
        for (uint256 i = 0; i < _hooks.length; i++) {
            $.planHooks[_planId].push(_hooks[i]);
        }
    }

    /**
     * @notice Sets a custom fee controller for a plan
     * @param _planId The ID of the plan
     * @param _feeControllerAddress Address of the fee controller contract
     * @dev Only callable by the plan owner
     */
    function setPlanFeeController(uint256 _planId, IFeeController _feeControllerAddress) external restricted {
        AssetsRegistryStorage storage $ = _getAssetsRegistryStorage();

        if ($.plans[_planId].lastUpdated == 0) {
            revert PlanNotFound(_planId);
        }

        $.plans[_planId].price.feeController = _feeControllerAddress;
        $.plans[_planId].lastUpdated = block.timestamp;

        emit PlanFeeControllerUpdated(_planId, address(_feeControllerAddress));
    }
}
