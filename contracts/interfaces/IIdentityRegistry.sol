// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @title IIdentityRegistry
 * @notice Interface for ERC-8004 Identity Registry
 * @dev This interface defines the standard for agent identity registration on blockchain
 * @dev Each agent is uniquely identified by namespace:chainId:identityRegistry:agentId
 * @dev Based on ERC-8004: Trustless Agents specification
 */
interface IIdentityRegistry is IERC721 {
    /* ERRORS */
    /**
     * @notice Thrown when the caller is not authorized to perform an action
     */
    error NotAuthorized();

    /**
     * @notice Thrown when attempting to transfer a non-transferable identity token
     */
    error TransfersDisabled();

    /**
     * @notice Thrown when attempting to get next agent ID for hash-based registries
     */
    error AgentIdsAreHashBased();

    /**
     * @notice Emitted when an agent is registered
     * @param agentId The unique identifier of the registered agent
     * @param tokenURI The URI pointing to the agent's registration file
     * @param owner The address that owns the agent
     */
    event Registered(uint256 indexed agentId, string tokenURI, address indexed owner);

    /**
     * @notice Emitted when agent metadata is set
     * @param agentId The unique identifier of the agent
     * @param indexedKey The indexed key for efficient filtering
     * @param key The metadata key
     * @param value The metadata value
     */
    event MetadataSet(uint256 indexed agentId, string indexed indexedKey, string key, bytes value);

    /**
     * @notice Metadata entry structure for agent registration
     * @param key The metadata key
     * @param value The metadata value
     */
    struct MetadataEntry {
        string key;
        bytes value;
    }

    /**
     * @notice Register a new agent with token URI and metadata
     * @param tokenURI The URI pointing to the agent's registration file
     * @param metadata Array of metadata entries to set for the agent
     * @return agentId The unique identifier assigned to the registered agent
     * @dev The tokenURI must resolve to a valid agent registration file
     * @dev Emits Registered and MetadataSet events
     */
    function register(string calldata tokenURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);

    /**
     * @notice Register a new agent with token URI only
     * @param tokenURI The URI pointing to the agent's registration file
     * @return agentId The unique identifier assigned to the registered agent
     * @dev The tokenURI must resolve to a valid agent registration file
     * @dev Emits Registered event
     */
    function register(string calldata tokenURI) external returns (uint256 agentId);

    /**
     * @notice Register a new agent without initial token URI
     * @return agentId The unique identifier assigned to the registered agent
     * @dev The tokenURI can be set later using _setTokenURI()
     * @dev Emits Registered event
     */
    function register() external returns (uint256 agentId);

    /**
     * @notice Get agent metadata by key
     * @param agentId The unique identifier of the agent
     * @param key The metadata key to retrieve
     * @return value The metadata value associated with the key
     * @dev Returns empty bytes if the key doesn't exist
     */
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory value);

    /**
     * @notice Set agent metadata
     * @param agentId The unique identifier of the agent
     * @param key The metadata key
     * @param value The metadata value
     * @dev Only the owner or approved operator can set metadata
     * @dev Emits MetadataSet event
     */
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;

    /**
     * @notice Get the next available agent ID
     * @return agentId The next agent ID that will be assigned
     * @dev Useful for frontend applications to predict the next ID
     */
    function getNextAgentId() external view returns (uint256 agentId);

    /**
     * @notice Get the total number of registered agents
     * @return count The total number of agents registered
     */
    function getTotalAgents() external view returns (uint256 count);

    /**
     * @notice Check if an agent ID exists
     * @param agentId The unique identifier to check
     * @return exists True if the agent ID exists, false otherwise
     */
    function agentExists(uint256 agentId) external view returns (bool exists);
}
