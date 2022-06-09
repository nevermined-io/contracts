const { Report } = require('./report')
const fs = require('fs')

const contracts = [
    'NeverminedConfig',
    'AccessCondition',
    'AccessTemplate',
    'AgreementStoreLibrary',
    'AgreementStoreManager',
    'AgreementTemplate',
    'Common',
    'ComputeExecutionCondition',
    'ConditionStoreManager',
    'ConditionStoreLibrary',
    'Condition',
    'Dispenser',
    'DIDFactory',
    'DIDRegistry',
    'DIDRegistryLibrary',
    'DIDSalesTemplate',
    'DynamicAccessTemplate',
    'EpochLibrary',
    'EscrowComputeExecutionTemplate',
    'EscrowPaymentCondition',
    'HashListLibrary',
    'HashLists',
    'HashLockCondition',
    'ISecretStore',
    'LockPaymentCondition',
    'NeverminedToken',
    'NFTAccessCondition',
    'NFTAccessTemplate',
    'NFTHolderCondition',
    'NFTLockCondition',
    'NFTSalesTemplate',
    'NFTUpgradeable',
    'ProvenanceRegistry',
    'Reward',
    'SignCondition',
    'TemplateStoreLibrary',
    'TemplateStoreManager',
    'TransferDIDOwnershipCondition',
    'TransferNFTCondition',
    'ThresholdCondition',
    'WhitelistingCondition'
]

contracts.forEach((contractName) => {
    const doc = new Report(contractName).generate()
    fs.writeFileSync(`./docs/contracts/${contractName}.md`, doc)
})
