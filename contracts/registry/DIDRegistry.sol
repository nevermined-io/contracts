pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Common.sol';
import './DIDFactory.sol';
import '../token/erc1155/NFTUpgradeable.sol';
import '../token/erc721/NFT721Upgradeable.sol';
import '../royalties/StandardRoyalties.sol';

/**
 * @title Mintable DID Registry
 * @author Nevermined
 *
 * @dev Implementation of a Mintable DID Registry.
 */
contract DIDRegistry is DIDFactory {

    using DIDRegistryLibrary for DIDRegistryLibrary.DIDRegisterList;

    NFTUpgradeable public erc1155;
    NFT721Upgradeable public erc721;

    mapping (address => bool) public royaltiesCheckers;
    StandardRoyalties public defaultRoyalties;

    INVMConfig public nvmConfig;
    address public conditionManager;

    modifier onlyConditionManager
    {
        require(
            _msgSender() == conditionManager,
            'Only condition store manager'
        );
        _;
    }

    //////////////////////////////////////////////////////////////
    ////////  EVENTS  ////////////////////////////////////////////
    //////////////////////////////////////////////////////////////
    
    /**
     * @dev DIDRegistry Initializer
     *      Initialize Ownable. Only on contract creation.
     * @param _owner refers to the owner of the contract.
     */
    function initialize(
        address _owner,
        address _erc1155,
        address _erc721,
        address _config,
        address _royalties
    )
    public
    initializer
    {
        OwnableUpgradeable.__Ownable_init();
        erc1155 = NFTUpgradeable(_erc1155);
        erc721 = NFT721Upgradeable(_erc721);
        transferOwnership(_owner);
        manager = _owner;
        defaultRoyalties = StandardRoyalties(_royalties);
        nvmConfig = INVMConfig(_config);
    }

    function setDefaultRoyalties(address _royalties) public onlyOwner {
        defaultRoyalties = StandardRoyalties(_royalties);
    }

    function registerRoyaltiesChecker(address _addr) public onlyOwner {
        royaltiesCheckers[_addr] = true;
    }

    function setConditionManager(address _manager) public onlyOwner {
        conditionManager = _manager;
    }

    event DIDRoyaltiesAdded(bytes32 indexed did, address indexed addr);
    event DIDRoyaltyRecipientChanged(bytes32 indexed did, address indexed addr);

    function setDIDRoyalties(
        bytes32 _did,
        address _royalties
    )
    public
    {
        require(didRegisterList.didRegisters[_did].creator == _msgSender(), 'Only creator can set royalties');
        require(address(didRegisterList.didRegisters[_did].royaltyScheme) == address(0), 'Cannot change royalties');
        didRegisterList.didRegisters[_did].royaltyScheme = IRoyaltyScheme(_royalties);

        emit DIDRoyaltiesAdded(
            _did,
            _royalties
        );
    }

    function setDIDRoyaltyRecipient(
        bytes32 _did,
        address _recipient
    )
    public
    {
        require(didRegisterList.didRegisters[_did].creator == _msgSender(), 'Only creator can set royalties');
        didRegisterList.didRegisters[_did].royaltyRecipient = _recipient;

        emit DIDRoyaltyRecipientChanged(
            _did,
            _recipient
        );
    }

    /**
     * @notice Register a Mintable DID using NFTs based in the ERC-1155 standard.
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
     * @param _mint if true it mints the ERC-1155 NFTs attached to the asset
     * @param _activityId refers to activity
     * @param _nftMetadata refers to the url providing the NFT Metadata 
     * @param _immutableUrl includes the url to the DDO in immutable storage              
     */
    function registerMintableDID(
        bytes32 _didSeed,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _cap,
        uint256 _royalties,
        bool _mint,
        bytes32 _activityId,
        string memory _nftMetadata,
        string memory _immutableUrl
    )
    public
    onlyValidAttributes(_nftMetadata)
    {
        registerDID(_didSeed, _checksum, _providers, _url, _activityId, _immutableUrl);
        enableAndMintDidNft(
            hashDID(_didSeed, _msgSender()),
            _cap,
            _royalties,
            _mint,
            _nftMetadata
        );
    }

    /**
     * @notice Register a Mintable DID using NFTs based in the ERC-721 standard.
     *
     * @dev The first attribute of a DID registered sets the DID owner.
     *      Subsequent updates record _checksum and update info.
     *
     * @param _didSeed refers to decentralized identifier seed (a bytes32 length ID).
     * @param _checksum includes a one-way HASH calculated using the DDO content.
     * @param _providers list of addresses that can act as an asset provider     
     * @param _url refers to the url resolving the DID into a DID Document (DDO), limited to 2048 bytes.
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if true it mints the ERC-1155 NFTs attached to the asset
     * @param _activityId refers to activity
     * @param _nftMetadata refers to the url providing the NFT Metadata
     * @param _immutableUrl includes the url to the DDO in immutable storage       
     */
    function registerMintableDID721(
        bytes32 _didSeed,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _royalties,
        bool _mint,
        bytes32 _activityId,
        string memory _nftMetadata,
        string memory _immutableUrl
    )
    public
    {
        registerDID(_didSeed, _checksum, _providers, _url, _activityId, _immutableUrl);
        enableAndMintDidNft721(
            hashDID(_didSeed, _msgSender()),
            _royalties,
            _mint
        );
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
     * @param _nftMetadata refers to the url providing the NFT Metadata
     * @param _immutableUrl includes the url to the DDO in immutable storage               
     */
    function registerMintableDID(
        bytes32 _didSeed,
        bytes32 _checksum,
        address[] memory _providers,
        string memory _url,
        uint256 _cap,
        uint256 _royalties,
        bytes32 _activityId,
        string memory _nftMetadata,
        string memory _immutableUrl
    )
    public
    onlyValidAttributes(_nftMetadata)
    {
        registerMintableDID(
            _didSeed, _checksum, _providers, _url, _cap, _royalties, false, _activityId, _nftMetadata, _immutableUrl);
    }

    
    /**
     * @notice enableDidNft creates the initial setup of NFTs minting and royalties distribution for ERC-1155 NFTs.
     * After this initial setup, this data can't be changed anymore for the DID given, even for the owner of the DID.
     * The reason of this is to avoid minting additional NFTs after the initial agreement, what could affect the 
     * valuation of NFTs of a DID already created.
      
     * @dev update the DID registry providers list by adding the mintCap and royalties configuration
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _cap refers to the mint cap
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if is true mint directly the amount capped tokens and lock in the _lockAddress
     * @param _nftMetadata refers to the url providing the NFT Metadata          
     */
    function enableAndMintDidNft(
        bytes32 _did,
        uint256 _cap,
        uint256 _royalties,
        bool _mint,
        string memory _nftMetadata
    )
    public
    onlyDIDOwner(_did)
    returns (bool success)
    {
        didRegisterList.initializeNftConfig(_did, _cap, _royalties > 0 ? defaultRoyalties : IRoyaltyScheme(address(0)));
        
        if (bytes(_nftMetadata).length > 0)
            erc1155.setNFTMetadata(uint256(_did), _nftMetadata);
        
        if (_royalties > 0) {
            erc1155.setTokenRoyalty(uint256(_did), _msgSender(), _royalties);
            if (address(defaultRoyalties) != address(0)) defaultRoyalties.setRoyalty(_did, _royalties);
        }
        
        if (_mint)
            mint(_did, _cap);
        
        return super.used(
            keccak256(abi.encode(_did, _cap, _royalties, _msgSender())),
            _did, _msgSender(), keccak256('enableNft'), '', 'nft initialization');
    }

    /**
     * @notice enableAndMintDidNft721 creates the initial setup of NFTs minting and royalties distribution for ERC-721 NFTs.
     * After this initial setup, this data can't be changed anymore for the DID given, even for the owner of the DID.
     * The reason of this is to avoid minting additional NFTs after the initial agreement, what could affect the 
     * valuation of NFTs of a DID already created.
      
     * @dev update the DID registry providers list by adding the mintCap and royalties configuration
     * @param _did refers to decentralized identifier (a byte32 length ID)
     * @param _royalties refers to the royalties to reward to the DID creator in the secondary market
     * @param _mint if is true mint directly the amount capped tokens and lock in the _lockAddress          
     */    
    function enableAndMintDidNft721(
        bytes32 _did,
        uint256 _royalties,
        bool _mint
    )
    public
    onlyDIDOwner(_did)
    returns (bool success)
    {
        didRegisterList.initializeNft721Config(_did, _royalties > 0 ? defaultRoyalties : IRoyaltyScheme(address(0)));
        
        if (_royalties > 0) {
            if (address(defaultRoyalties) != address(0)) defaultRoyalties.setRoyalty(_did, _royalties);
            erc721.setTokenRoyalty(uint256(_did), _msgSender(), _royalties);
        }

        if (_mint)
            mint721(_did, _msgSender());
        
        return super.used(
            keccak256(abi.encode(_did, 1, _royalties, _msgSender())),
            _did, _msgSender(), keccak256('enableNft721'), '', 'nft initialization');
    }

    /**
     * @notice Mints a NFT associated to the DID
     *
     * @dev Because ERC-1155 uses uint256 and DID's are bytes32, there is a conversion between both
     *      Only the DID owner can mint NFTs associated to the DID
     *
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _amount amount to mint
     * @param _receiver the address that will receive the new nfts minted
     */    
    function mint(
        bytes32 _did,
        uint256 _amount,
        address _receiver
    )
    public
    onlyDIDOwner(_did)
    nftIsInitialized(_did)
    {
        if (didRegisterList.didRegisters[_did].mintCap > 0) {
            require(
                didRegisterList.didRegisters[_did].nftSupply + _amount <= didRegisterList.didRegisters[_did].mintCap,
                'Cap exceeded'
            );
        }
        
        didRegisterList.didRegisters[_did].nftSupply = didRegisterList.didRegisters[_did].nftSupply + _amount;
        
        super.used(
            keccak256(abi.encode(_did, _msgSender(), 'mint', _amount, block.number)),
            _did, _msgSender(), keccak256('mint'), '', 'mint');

        erc1155.mint(_receiver, uint256(_did), _amount, '');
    }

    function mint(
        bytes32 _did,
        uint256 _amount
    )
    public
    {
        mint(_did, _amount, _msgSender());
    }


    /**
     * @notice Mints a ERC-721 NFT associated to the DID
     *
     * @param _did refers to decentralized identifier (a bytes32 length ID).
     * @param _receiver the address that will receive the new nfts minted
     */
    function mint721(
        bytes32 _did,
        address _receiver
    )
    public
    onlyDIDOwner(_did)
    nft721IsInitialized(_did)
    {
        erc721.mint(_receiver, uint256(_did));
        super.used(
            keccak256(abi.encode(_did, _msgSender(), 'mint721', 1, block.number)),
            _did, _msgSender(), keccak256('mint721'), '', 'mint721');
    }

    function mint721(
        bytes32 _did
    )
    public
    {
        mint721(_did, _msgSender());
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
    nftIsInitialized(_did)
    {
        erc1155.burn(_msgSender(), uint256(_did), _amount);
        didRegisterList.didRegisters[_did].nftSupply -= _amount;
        
        super._used(
            keccak256(abi.encode(_did, _msgSender(), 'burn', _amount, block.number)),
            _did, _msgSender(), keccak256('burn'), '', 'burn');
    }

    function burn721(
        bytes32 _did,
        uint256 _tokenId
    )
    public
    nft721IsInitialized(_did)
    {
        require(erc721.ownerOf(_tokenId) == _msgSender(), 'ERC721: burn amount exceeds balance');
        erc721.burn(uint256(_tokenId));

        super._used(
            keccak256(abi.encode(_did, _msgSender(), 'burn721', 1, block.number)),
            _did, _msgSender(), keccak256('burn721'), '', 'burn721');
    }

    function _provenanceStorage() override internal view returns (bool) {
        return address(nvmConfig) == address(0) || nvmConfig.getProvenanceStorage();
    }

    function condition(bytes32 _did, bytes32 _cond, string memory name, address user) public onlyConditionManager {
        _used(_cond, _did, user, keccak256(bytes(name)), '', name);
    }

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        return address(nvmConfig);
    }
}
