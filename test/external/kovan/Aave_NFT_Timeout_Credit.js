/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, network */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const BigNumber = require('bignumber.js')

const NeverminedConfig = artifacts.require('NeverminedConfig')
const AaveCreditTemplate = artifacts.require('AaveCreditTemplate')
const NFTLockCondition = artifacts.require('NFT721LockCondition')
const TransferNFTCondition = artifacts.require('DistributeNFTCollateralCondition')
const AaveCollateralDeposit = artifacts.require('AaveCollateralDepositCondition')
const AaveBorrowCredit = artifacts.require('AaveBorrowCondition')
const AaveRepayCredit = artifacts.require('AaveRepayCondition')
const AaveCollateralWithdraw = artifacts.require('AaveCollateralWithdrawCondition')
const EpochLibrary = artifacts.require('EpochLibrary')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistry = artifacts.require('DIDRegistry')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const TemplateStoreManager = artifacts.require('TemplateStoreManager')
const AgreementStoreManager = artifacts.require('AgreementStoreManager')
const NeverminedToken = artifacts.require('NeverminedToken')
const AaveCreditVault = artifacts.require('AaveCreditVault')
const ERC20Upgradeable = artifacts.require('ERC20Upgradeable')
const TestERC721 = artifacts.require('TestERC721')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('End to End NFT Collateral Scenario (timeout) [@skip-on-coverage]', (accounts) => {
    const lender = accounts[3]
    const borrower = accounts[4]

    const lendingPoolAddress = '0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe' // Kovan
    const dataProviderAddress = '0x744C1aaA95232EeF8A9994C4E0b3a89659D9AB79' // Kovan
    const wethAddress = '0xA61ca04DF33B72b235a8A28CfB535bb7A5271B70' // Kovan
    const collateralAsset = '0xd0A1E359811322d97991E03f863a0C30C2cF029C' // WETH
    const delegatedAsset = '0xff795577d9ac8bd7d90ee22b6c1703490b6512fd' // DAI
    const delegatedAmount = '500000000000000000000' // 500 DAI
    const collateralAmount = '10000000000000000000' // 10 ETH
    const daiProvider = '0xAFD49D613467c0DaBf47B8f5C841089d96Cf7167'
    const agreementFee = '15'
    const INTEREST_RATE_MODE = 1

    const governor = accounts[2]
    const owner = accounts[8]
    const deployer = accounts[8]
    const treasuryAddress = accounts[5]
    const didSeed = testUtils.generateId()

    let
        aaveCreditTemplate,
        didRegistry,
        token,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        nftLockCondition,
        transferNftCondition,
        aaveCollateralDeposit,
        aaveBorrowCredit,
        aaveRepayCredit,
        aaveWithdrawnCollateral,
        erc721,
        nftTokenAddress,
        vaultAddress,
        did,
        agreementId,
        agreement

    async function setupTest() {
        token = await NeverminedToken.new()
        await token.initialize(owner, owner)

        const nvmConfig = await NeverminedConfig.new()
        await nvmConfig.initialize(owner, governor)

        const didRegistryLibrary = await DIDRegistryLibrary.new()
        await DIDRegistry.link(didRegistryLibrary)
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero)

        const epochLibrary = await EpochLibrary.new()
        await ConditionStoreManager.link(epochLibrary)
        conditionStoreManager = await ConditionStoreManager.new()

        templateStoreManager = await TemplateStoreManager.new()
        await templateStoreManager.initialize(owner, { from: deployer })

        agreementStoreManager = await AgreementStoreManager.new()
        await agreementStoreManager.methods['initialize(address,address,address,address)'](
            owner,
            conditionStoreManager.address,
            templateStoreManager.address,
            didRegistry.address,
            { from: deployer }
        )

        await conditionStoreManager.initialize(
            agreementStoreManager.address,
            owner,
            nvmConfig.address,
            { from: deployer }
        )

        nftLockCondition = await NFTLockCondition.new()

        await nftLockCondition.initialize(
            owner,
            conditionStoreManager.address,
            { from: owner }
        )

        transferNftCondition = await TransferNFTCondition.new()

        await transferNftCondition.initialize(
            owner,
            conditionStoreManager.address,
            nftLockCondition.address,
            { from: owner }
        )

        aaveCollateralDeposit = await AaveCollateralDeposit.new()

        await aaveCollateralDeposit.initialize(
            lender,
            conditionStoreManager.address,
            { from: owner }
        )

        aaveBorrowCredit = await AaveBorrowCredit.new()

        await aaveBorrowCredit.initialize(
            owner,
            conditionStoreManager.address,
            { from: owner }
        )

        aaveRepayCredit = await AaveRepayCredit.new()

        await aaveRepayCredit.initialize(
            owner,
            conditionStoreManager.address,
            { from: owner }
        )

        aaveWithdrawnCollateral = await AaveCollateralWithdraw.new()

        await aaveWithdrawnCollateral.initialize(
            owner,
            conditionStoreManager.address,
            { from: owner }
        )

        const aaveCreditVault = await AaveCreditVault.new()
        // Setup NFT Collaterall Template
        aaveCreditTemplate = await AaveCreditTemplate.new()
        await aaveCreditTemplate.initialize(
            owner,
            agreementStoreManager.address,
            nftLockCondition.address,
            aaveCollateralDeposit.address,
            aaveBorrowCredit.address,
            aaveRepayCredit.address,
            aaveWithdrawnCollateral.address,
            transferNftCondition.address,
            aaveCreditVault.address,
            { from: deployer }
        )

        erc721 = await TestERC721.new()
        await erc721.initialize({ from: owner })
        nftTokenAddress = erc721.address

        await templateStoreManager.proposeTemplate(aaveCreditTemplate.address)
        await templateStoreManager.approveTemplate(aaveCreditTemplate.address, { from: owner })

        const templateId = aaveCreditTemplate.address

        return {
            didRegistry,
            templateId,
            aaveCreditTemplate,
            treasuryAddress
        }
    }

    async function prepareCreditTemplate({
        initAgreementId = testUtils.generateId(),
        sender = accounts[0],
        _borrower = borrower,
        _lender = lender,
        timeLockAccess = 0,
        timeOutAccess = 0,
        did = testUtils.generateId(),
        checksum = constants.bytes32.one,
        url = constants.registry.url
    } = {}) {
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, borrower)
        // generate IDs from attributes
        const conditionIdLock = await nftLockCondition.hashValues(did, vaultAddress, 1, nftTokenAddress)
        const fullIdLock = await nftLockCondition.generateId(agreementId, conditionIdLock)

        const conditionIdDeposit = await aaveCollateralDeposit.hashValues(did, vaultAddress, collateralAsset, collateralAmount, delegatedAsset, delegatedAmount, INTEREST_RATE_MODE)
        const fullIdDeposit = await aaveCollateralDeposit.generateId(agreementId, conditionIdDeposit)

        const conditionIdBorrow =
            await aaveBorrowCredit.hashValues(
                did,
                vaultAddress,
                delegatedAsset,
                delegatedAmount,
                INTEREST_RATE_MODE)
        const fullIdBorrow = await aaveBorrowCredit.generateId(agreementId, conditionIdBorrow)
        const conditionIdRepay =
            await aaveRepayCredit.hashValues(
                did,
                vaultAddress,
                delegatedAsset,
                delegatedAmount,
                INTEREST_RATE_MODE
            )
        const fullIdRepay = await aaveRepayCredit.generateId(agreementId, conditionIdRepay)
        const conditionIdWithdraw =
            await aaveWithdrawnCollateral.hashValues(
                did,
                vaultAddress,
                collateralAsset
            )
        const fullIdWithdraw = await aaveWithdrawnCollateral.generateId(agreementId, conditionIdWithdraw)
        const conditionIdTransfer = await transferNftCondition.hashValues(did, vaultAddress, nftTokenAddress)
        const fullIdTransfer = await transferNftCondition.generateId(agreementId, conditionIdTransfer)

        // construct agreement
        const agreement = {
            id: initAgreementId,
            did,
            conditionIds: [
                conditionIdLock,
                conditionIdDeposit,
                conditionIdBorrow,
                conditionIdRepay,
                conditionIdWithdraw,
                conditionIdTransfer
            ],
            timeLocks: [0, 0, 0, timeLockAccess, 0, 0],
            timeOuts: [0, 0, 0, timeOutAccess, 0, 0],
            lender: _lender
        }
        return {
            conditionIds: [
                fullIdLock,
                fullIdDeposit,
                fullIdBorrow,
                fullIdRepay,
                fullIdWithdraw,
                fullIdTransfer
            ],
            agreementId,
            did,
            agreement,
            sender,
            timeLockAccess,
            timeOutAccess,
            checksum,
            vaultAddress,
            url
        }
    }

    describe('Create a credit NFT collateral agreement', function() {
        let conditionIds
        this.timeout(100000)
        it('Create a credit agreement', async () => {
            await network.provider.request({
                method: 'hardhat_impersonateAccount',
                params: ['0xAFD49D613467c0DaBf47B8f5C841089d96Cf7167']
            })
            const { didRegistry, aaveCreditTemplate } = await setupTest()

            const result = await aaveCreditTemplate.deployVault(
                lendingPoolAddress,
                dataProviderAddress,
                wethAddress,
                agreementFee,
                treasuryAddress,
                borrower,
                lender,
                { from: lender }
            )
            const eventArgs = testUtils.getEventArgsFromTx(result, 'VaultCreated')
            vaultAddress = eventArgs._vaultAddress

            did = await didRegistry.hashDID(didSeed, borrower)

            const {
                agreementId: _agreementId,
                agreement: _agreement,
                checksum,
                url,
                conditionIds: _ids
            } = await prepareCreditTemplate({ did: did, timeOutAccess: 1 })
            agreementId = _agreementId
            agreement = _agreement
            conditionIds = _ids

            await didRegistry.registerAttribute(didSeed, checksum, [], url, { from: borrower })
            await erc721.mint(did, { from: borrower })
            await erc721.approve(nftLockCondition.address, did, { from: borrower })

            // Create agreement
            await aaveCreditTemplate.methods['createVaultAgreement(bytes32,bytes32,bytes32[],uint256[],uint256[],address)'](
                agreement.id,
                agreement.did,
                agreement.conditionIds,
                agreement.timeLocks,
                agreement.timeOuts,
                vaultAddress,
                { from: borrower }
            )

            // External user try to update nevermined fee
            await assert.isRejected(aaveCreditTemplate.updateNVMFee(10, { from: borrower }))

            // Owner updates nevermined fee
            await aaveCreditTemplate.updateNVMFee(3, { from: owner })
        })

        it('The borrower locks the NFT', async () => {
            // The borrower locks the NFT in the vault
            await nftLockCondition.fulfill(
                agreementId, did, vaultAddress, 1, nftTokenAddress, { from: borrower }
            )
            const { state: stateNftLock } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(stateNftLock.toNumber(), constants.condition.state.fulfilled)
            assert.strictEqual(vaultAddress, await erc721.ownerOf(did))
        })

        it('Lender deposits ETH as collateral in Aave and approves borrower to borrow DAI', async () => {
            // Fullfill the deposit collateral condition
            await aaveCollateralDeposit.fulfill(
                agreementId,
                did,
                vaultAddress,
                collateralAsset,
                collateralAmount,
                delegatedAsset,
                delegatedAmount,
                INTEREST_RATE_MODE,
                {
                    from: lender,
                    value: collateralAmount
                }
            )
            const { state: stateDeposit } = await conditionStoreManager.getCondition(
                conditionIds[1])
            assert.strictEqual(stateDeposit.toNumber(), constants.condition.state.fulfilled)

            // Vault instance
            const vault = await AaveCreditVault.at(vaultAddress)

            // Get the actual delegated amount for the delgatee in this specific asset
            const actualAmount = await vault.delegatedAmount(
                borrower,
                delegatedAsset,
                INTEREST_RATE_MODE
            )

            // The delegated borrow amount in the vault should be the same that the
            // Delegegator allowed on deposit
            assert.strictEqual(actualAmount.toString(), delegatedAmount)
        })

        it('Borrower/Delegatee borrows DAI from Aave on behalf of Delegator', async () => {
            const dai = await ERC20Upgradeable.at(delegatedAsset)
            const before = await dai.balanceOf(borrower)

            // Fullfill the aaveBorrowCredit condition
            // Delegatee borrows DAI from Aave on behalf of Delegator
            await aaveBorrowCredit.fulfill(
                agreementId,
                did,
                vaultAddress,
                delegatedAsset,
                delegatedAmount,
                INTEREST_RATE_MODE,
                {
                    from: borrower
                }
            )
            const { state: stateCredit } = await conditionStoreManager.getCondition(
                conditionIds[2])
            assert.strictEqual(stateCredit.toNumber(), constants.condition.state.fulfilled)

            const after = await dai.balanceOf(borrower)
            assert.strictEqual(BigNumber(after).minus(BigNumber(before)).toNumber(), BigNumber(delegatedAmount).toNumber())
        })

        it('Borrower/Delegatee can not get back the NFT without repay the loan', async () => {
            await assert.isRejected(
                transferNftCondition.fulfill(
                    agreementId,
                    did,
                    vaultAddress,
                    nftTokenAddress,
                    { from: borrower }
                )
            )
            const { state: stateTransfer } = await conditionStoreManager.getCondition(conditionIds[5])
            assert.strictEqual(stateTransfer.toNumber(), constants.condition.state.unfulfilled)
        })

        it('Borrower/Delegatee can not repays the loan with DAI because is timed out', async () => {
            const vault = await AaveCreditVault.at(vaultAddress)
            const totalDebt = await vault.getTotalActualDebt()
            const dai = await ERC20Upgradeable.at(delegatedAsset)
            const allowanceAmount = Number(totalDebt) + (Number(totalDebt) / 10000 * 10)

            // Delegatee allows Nevermined contracts spend DAI to repay the loan
            await dai.approve(aaveRepayCredit.address, allowanceAmount.toString(),
                { from: borrower })

            // Send some DAI to borrower to pay the debt + fees
            await dai.transfer(
                borrower,
                (Number(totalDebt) - Number(delegatedAmount)).toString(),
                { from: daiProvider })

            const before = await dai.balanceOf(borrower)

            // Fullfill the aaveRepayCredit condition
            await aaveRepayCredit.fulfill(
                agreementId,
                did,
                vaultAddress,
                delegatedAsset,
                delegatedAmount,
                INTEREST_RATE_MODE,
                { from: borrower }
            )
            const { state: stateRepay } = await conditionStoreManager.getCondition(conditionIds[3])
            assert.strictEqual(stateRepay.toNumber(), constants.condition.state.aborted)

            const after = await dai.balanceOf(borrower)
            assert.strictEqual(BigNumber(after).toNumber(), BigNumber(before).toNumber())
        })

        it('Delegator withdraw collateral and fees', async () => {
            // Fullfill the AaveCollateralWithdraw condition
            await assert.isRejected(
                aaveWithdrawnCollateral.fulfill(
                    agreementId,
                    did,
                    vaultAddress,
                    collateralAsset,
                    { from: lender }
                ),
                /Repay Condition needs to be Fulfilled/
            )
            const { state: stateWithdraw } = await conditionStoreManager.getCondition(conditionIds[4])
            assert.strictEqual(stateWithdraw.toNumber(), constants.condition.state.unfulfilled)
        })

        it('Borrower/Delegatee paid the credit so will get back the NFT', async () => {
            await transferNftCondition.fulfill(
                agreementId,
                did,
                vaultAddress,
                nftTokenAddress,
                { from: lender }
            )

            const { state: stateTransfer } = await conditionStoreManager.getCondition(conditionIds[5])
            assert.strictEqual(stateTransfer.toNumber(), constants.condition.state.fulfilled)
        })
    })
})
