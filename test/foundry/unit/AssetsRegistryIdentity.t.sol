// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAsset} from '../../../contracts/interfaces/IAsset.sol';
import {IIdentityRegistry} from '../../../contracts/interfaces/IIdentityRegistry.sol';
import {BaseTest} from '../common/BaseTest.sol';

contract AssetsRegistryIdentityTest is BaseTest {
    function test_register_mints_nft_and_sets_tokenURI() public {
        bytes32 agentSeed = keccak256('asset-1');
        string memory uri = 'ipfs://asset-1.json';
        uint256[] memory plans = new uint256[](0);

        vm.prank(governor);
        uint256 tokenId = assetsRegistry.register(agentSeed, uri, plans);

        uint256 agentId = tokenId;
        assertEq(assetsRegistry.ownerOf(tokenId), governor);
        assertEq(assetsRegistry.tokenURI(tokenId), uri);
        assertTrue(assetsRegistry.agentExists(tokenId));
        assertEq(assetsRegistry.getTotalAgents(), 1);

        // Verify asset was registered with correct DID
        IAsset.DIDAgent memory asset = assetsRegistry.getAgent(agentId);
        assertEq(asset.owner, governor);
    }

    function test_register_with_metadata_sets_entries() public {
        bytes32 seed = keccak256('asset-2');
        string memory uri = 'ipfs://asset-2.json';
        uint256[] memory plans = new uint256[](0);
        IIdentityRegistry.MetadataEntry[] memory metadata = new IIdentityRegistry.MetadataEntry[](2);
        metadata[0] = IIdentityRegistry.MetadataEntry({key: 'name', value: abi.encode('Agent 2')});
        metadata[1] = IIdentityRegistry.MetadataEntry({key: 'desc', value: abi.encode('Second agent')});

        vm.prank(governor);
        uint256 tokenId = assetsRegistry.register(seed, uri, plans);

        vm.startPrank(governor);
        for (uint256 i = 0; i < metadata.length; i++) {
            assetsRegistry.setMetadata(tokenId, metadata[i].key, metadata[i].value);
        }
        vm.stopPrank();

        bytes memory nameV = assetsRegistry.getMetadata(tokenId, 'name');
        assertEq(abi.decode(nameV, (string)), 'Agent 2');

        bytes memory descV = assetsRegistry.getMetadata(tokenId, 'desc');
        assertEq(abi.decode(descV, (string)), 'Second agent');
    }

    function test_transfers_disabled() public {
        bytes32 seed = keccak256('asset-3');
        string memory uri = 'ipfs://asset-3.json';
        uint256[] memory plans = new uint256[](0);

        vm.prank(governor);
        uint256 tokenId = assetsRegistry.register(seed, uri, plans);

        vm.prank(governor);
        vm.expectRevert(IIdentityRegistry.TransfersDisabled.selector);
        assetsRegistry.transferFrom(governor, alice, tokenId);
    }

    function test_getNextAgentId_reverts() public {
        vm.expectRevert(IIdentityRegistry.AgentIdsAreHashBased.selector);
        assetsRegistry.getNextAgentId();
    }

    function test_register_erc8004_with_tokenURI_and_metadata() public {
        string memory tokenURI = 'ipfs://agent-1.json';
        IIdentityRegistry.MetadataEntry[] memory metadata = new IIdentityRegistry.MetadataEntry[](2);
        metadata[0] = IIdentityRegistry.MetadataEntry({key: 'name', value: abi.encode('Test Agent')});
        metadata[1] = IIdentityRegistry.MetadataEntry({key: 'description', value: abi.encode('A test agent')});

        vm.startPrank(governor);

        // Register will emit events, but we can't predict agentId beforehand
        // So we'll just verify the registration worked correctly
        uint256 agentId = assetsRegistry.register(tokenURI, metadata);

        assertEq(assetsRegistry.ownerOf(agentId), governor);
        assertEq(assetsRegistry.tokenURI(agentId), tokenURI);
        assertTrue(assetsRegistry.agentExists(agentId));
        assertEq(assetsRegistry.getTotalAgents(), 1);

        bytes memory nameValue = assetsRegistry.getMetadata(agentId, 'name');
        assertEq(abi.decode(nameValue, (string)), 'Test Agent');

        bytes memory descValue = assetsRegistry.getMetadata(agentId, 'description');
        assertEq(abi.decode(descValue, (string)), 'A test agent');

        vm.stopPrank();
    }

    function test_register_erc8004_with_tokenURI_only() public {
        string memory tokenURI = 'ipfs://agent-2.json';

        vm.prank(governor);
        uint256 agentId = assetsRegistry.register(tokenURI);

        assertEq(assetsRegistry.ownerOf(agentId), governor);
        assertEq(assetsRegistry.tokenURI(agentId), tokenURI);
        assertTrue(assetsRegistry.agentExists(agentId));
        assertEq(assetsRegistry.getTotalAgents(), 1);
    }

    function test_register_erc8004_without_tokenURI() public {
        vm.prank(governor);
        uint256 agentId = assetsRegistry.register();

        assertEq(assetsRegistry.ownerOf(agentId), governor);
        assertEq(assetsRegistry.tokenURI(agentId), '');
        assertTrue(assetsRegistry.agentExists(agentId));
        assertEq(assetsRegistry.getTotalAgents(), 1);
    }
}
