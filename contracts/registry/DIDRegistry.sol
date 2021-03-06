pragma solidity 0.6.12;
// Copyright 2020 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './DIDFactory.sol';
import '../token/erc1155/NFTUpgradeable.sol';

/**
 * @title Mintable DID Registry
 * @author Keyko
 *
 * @dev Implementation of a Mintable DID Registry.
 */
contract DIDRegistry is DIDFactory, NFTUpgradeable {
    

    //////////////////////////////////////////////////////////////
    ////////  EVENTS  ////////////////////////////////////////////
    //////////////////////////////////////////////////////////////
    
    /**
     * @dev DIDRegistry Initializer
     *      Initialize Ownable. Only on contract creation.
     * @param _owner refers to the owner of the contract.
     */
    function initialize(
        address _owner
    )
    public
    override
    initializer
    {
        OwnableUpgradeable.__Ownable_init();
        NFTUpgradeable.__NFTUpgradeable_init('');
        transferOwnership(_owner);
        manager = _owner;
    }

    /**
     * @notice Register a Mintable DID.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID).
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _providers list of addresses that can act as an asset provider     
     * @param _url refers to the url resolving the DID into a DID Document (DDO), limited to 2048 bytes.
     * @param _cap refers to the mint cap
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _activityId refers to activity
     * @param _attributes refers to the provenance attributes     
     * @return size refers to the size of the registry after the register action.
     */
    function registerMintableDID(
        bytes32 _didSeed,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _cap,
        uint8 _royalties,
        bytes32 _activityId,
        string memory _attributes
    )
    public
    onlyValidAttributes(_attributes)
    returns (uint size)
    {
        uint result = registerDID(_didSeed, _checksum, _providers, _url, _activityId, _attributes);
        enableAndMintDidNft(
            hashDID(_didSeed, msg.sender), 
            _cap, 
            _royalties, 
            false
        );
        return result;
    }

    
    /**
     * @notice enableDidNft creates the initial setup of NFTs minting and royalties distribution.
     * After this initial setup, this data can't be changed anymore for the DID given, even for the owner of the DID.
     * The reason of this is to avoid minting additional NFTs after the initial agreement, what could affect the 
     * valuation of NFTs of a DID already created.
      
     * @dev update the DID registry providers list by adding the mintCap and royalties configuration
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _cap refers to the mint cap
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _preMint if is true mint directly the amount capped tokens and lock in the _lockAddress
     */
    function enableAndMintDidNft(
        bytes32 _did,
        uint256 _cap,
        uint8 _royalties,
        bool _preMint
    )
    public
    onlyDIDOwner(_did)
    returns (bool success)
    {
        didRegisterList.initializeNftConfig(_did, _cap, _royalties);

        if (_preMint)    {
            mint(_did, _cap);
        }
        
        return super.used(
            keccak256(abi.encode(_did, _cap, _royalties, msg.sender)),
            _did, msg.sender, keccak256('enableNft'), '', 'nft initialization');
    }
    
    /**
     * @notice Mints a NFT associated to the DID
     *
     * @dev Because ERC-1155 uses uint256 and DID's are bytes32, there is a conversion between both
     *      Only the DID owner can mint NFTs associated to the DID
     *
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _amount amount to mint
     */    
    function mint(
        bytes32 _did,
        uint256 _amount
    )
    public
    onlyDIDOwner(_did)
    nftIsInitialized(_did)
    {
        if (didRegisterList.didRegisters[_did].mintCap > 0) {
            require(
                didRegisterList.didRegisters[_did].nftSupply.add(_amount) <= didRegisterList.didRegisters[_did].mintCap,
                'Cap exceeded'
            );
        }
        
        didRegisterList.didRegisters[_did].nftSupply = didRegisterList.didRegisters[_did].nftSupply.add(_amount);
        
        super.used(
            keccak256(abi.encode(_did, msg.sender, 'mint', _amount, block.number)),
            _did, msg.sender, keccak256('mint'), '', 'mint');

        super._mint(msg.sender, uint256(_did), _amount, '');
    }

    /**
     * @notice Burns NFTs associated to the DID
     *
     * @dev Because ERC-1155 uses uint256 and DID's are bytes32, there is a conversion between both
     *      Only the DID owner can burn NFTs associated to the DID
     *
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _amount amount to burn
     */
    function burn(
        bytes32 _did,
        uint256 _amount
    )
    public
    onlyDIDOwner(_did)
    nftIsInitialized(_did)
    {

        super._burn(msg.sender, uint256(_did), _amount);
        didRegisterList.didRegisters[_did].nftSupply -= _amount;

        super.used(
            keccak256(abi.encode(_did, msg.sender, 'burn', _amount, block.number)),
            _did, msg.sender, keccak256('burn'), '', 'burn');
    }
    
}
