import {
  keccak256,
  parseEventLogs,
  toBytes,
  WalletClient,
  encodeFunctionData,
  getAddress,
} from 'viem'

type CreditsBurnProofData = {
  keyspace: bigint
  nonce: bigint
  planIds: bigint[]
}

export function generateId(): `0x${string}` {
  return keccak256(toBytes(Math.random().toString()))
}

export function sha3(message: string): string {
  return keccak256(toBytes(message))
}

export async function getTxEvents(publicClient: any, txHash: string) {
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash })
  if (receipt.status !== 'success') return []
  return receipt.logs
}

export async function getTxParsedLogs(publicClient: any, txHash: string, abi: any) {
  const logs = await getTxEvents(publicClient, txHash)
  if (logs.length > 0) return parseEventLogs({ abi, logs }) as any[]
  return []
}

/**
 * Creates a price configuration object for asset registration
 * @param tokenAddress The address of the token to use for payment
 * @param creatorAddress The address of the asset creator
 * @returns Price configuration object
 */
export function createPriceConfig(tokenAddress: `0x${string}`, creatorAddress: `0x${string}`): any {
  return {
    isCrypto: true,
    tokenAddress: tokenAddress,
    amounts: [100n],
    receivers: [creatorAddress],
    externalPriceAddress: '0x0000000000000000000000000000000000000000',
    feeController: '0x0000000000000000000000000000000000000000',
    templateAddress: '0x0000000000000000000000000000000000000000',
  }
}

/**
 * Creates a credits configuration object for asset registration
 * @returns Credits configuration object
 */
export function createCreditsConfig(nftAddress: `0x${string}`): any {
  return {
    isRedemptionAmountFixed: true, // FIXED
    redemptionType: 0, // ONLY_GLOBAL_ROLE
    proofRequired: false,
    durationSecs: 0n,
    amount: 100n,
    minAmount: 1n,
    maxAmount: 1n,
    nftAddress: nftAddress,
  }
}

export const createCreditsBurnProof = (
  keyspace: bigint,
  nonce: bigint,
  planIds: bigint[],
): CreditsBurnProofData => ({
  keyspace,
  nonce,
  planIds,
})

export function createExpirableCreditsConfig(): any {
  return {
    isRedemptionAmountFixed: true, // Expirable
    redemptionType: 0, // ONLY_GLOBAL_ROLE
    durationSecs: 60n, // 60 secs
    amount: 100n,
    minAmount: 1n,
    maxAmount: 1n,
  }
}

/**
 * Registers an asset and plan in the AssetsRegistry
 * @param assetsRegistry The AssetsRegistry contract instance
 * @param tokenAddress The address of the token to use for payment
 * @param creator The creator account
 * @param creatorAddress The address of the creator
 * @returns Object containing the DID and planId of the registered asset
 */
export async function registerAgentAndPlan(
  assetsRegistry: any,
  priceConfig: any,
  creditsConfig: any,
  creator: any,
): Promise<{ agentId: `0x${string}`; planId: bigint }> {
  const seed = generateId()
  const agentId = await assetsRegistry.read.hashAgentId([seed, creator.account.address])

  const nonce = getRandomBigInt()
  const result = await assetsRegistry.read.includeFeesInPaymentsDistribution([
    priceConfig,
    creditsConfig,
  ])
  priceConfig.amounts = result[0]
  priceConfig.receivers = result[1]

  const planId = await assetsRegistry.read.hashPlanId([
    priceConfig,
    creditsConfig,
    creator.account.address,
    nonce,
  ])
  await assetsRegistry.write.createPlan([priceConfig, creditsConfig, nonce], {
    account: creator.account,
  })

  await assetsRegistry.write.register([seed, 'https://nevermined.io', [planId]], {
    account: creator.account,
  })

  return { agentId: agentId, planId }
}

/**
 * Creates an agreement in the AgreementsStore
 * @param agreementsStore The AgreementsStore contract instance
 * @param lockPaymentCondition The LockPaymentCondition contract instance
 * @param planId The planId of the asset
 * @param user The user account
 * @param template The template account
 * @returns Object containing the agreementId and conditionId
 */
export async function order(
  agreementsStore: any,
  lockPaymentCondition: any,
  planId: bigint,
  user: any,
  template: any,
): Promise<{ agreementId: `0x${string}`; conditionId: `0x${string}` }> {
  const agreementSeed = generateId()
  const agreementId = await agreementsStore.read.hashAgreementId([
    agreementSeed,
    user.account.address,
  ])

  const contractName = await lockPaymentCondition.read.NVM_CONTRACT_NAME()
  const conditionId = await lockPaymentCondition.read.hashConditionId([agreementId, contractName])

  await agreementsStore.write.register(
    [agreementId, user.account.address, planId, [conditionId], [0], 1, []],
    { account: template.account },
  )

  return { agreementId, conditionId }
}

export function getRandomBigInt(bits = 128): bigint {
  const bytes = Math.ceil(bits / 8)
  const array = new Uint8Array(bytes)
  crypto.getRandomValues(array)

  let result = 0n
  for (const byte of array) {
    result = (result << 8n) | BigInt(byte)
  }

  return result
}

export async function signCreditsBurnProof(
  walletClient: WalletClient,
  nft1155Address: `0x${string}`,
  proof: CreditsBurnProofData,
): Promise<`0x${string}`> {
  const domain = {
    name: 'NFT1155Base',
    version: '1',
    chainId: await walletClient.getChainId(),
    verifyingContract: nft1155Address,
  }

  const types = {
    CreditsBurnProofData: [
      { name: 'keyspace', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'planIds', type: 'uint256[]' },
    ],
  }

  const signature = await walletClient.signTypedData({
    account: walletClient.account!,
    domain,
    types,
    primaryType: 'CreditsBurnProofData',
    message: proof,
  })

  return signature
}

/**
 * Signs and prepares a forwarder request for ERC2771Forwarder
 * @param walletClient The wallet client to sign with
 * @param forwarderAddress The address of the ERC2771Forwarder contract
 * @param forwarderName The name of the forwarder (used in EIP-712 domain)
 * @param target The target contract address
 * @param data The function data to execute
 * @param value The value to send with the transaction
 * @param gas The gas limit for the transaction
 * @param deadline The deadline for the request (timestamp)
 * @returns The signed forwarder request data
 */
export async function signForwarderRequest(
  walletClient: WalletClient,
  forwarderAddress: `0x${string}`,
  forwarderName: string,
  target: `0x${string}`,
  data: `0x${string}`,
  forwarderContract: any = null, // Optional forwarder contract to read nonce
  value: bigint = 0n,
  gas: bigint = 100000n,
  deadline: bigint = BigInt(Math.floor(Date.now() / 1000) + 3600), // 1 hour from now
): Promise<{
  from: `0x${string}`
  to: `0x${string}`
  value: bigint
  gas: bigint
  deadline: bigint
  data: `0x${string}`
  signature: `0x${string}`
}> {
  const chainId = await walletClient.getChainId()
  const from = walletClient.account!.address

  // Get nonce from forwarder contract if provided, otherwise use 0
  let nonce = 0n
  if (forwarderContract) {
    try {
      nonce = await forwarderContract.read.nonces([from])
    } catch (e) {
      console.warn('Could not read nonce from forwarder, using 0:', e)
      nonce = 0n
    }
  }

  const domain = {
    name: forwarderName,
    version: '1',
    chainId: chainId,
    verifyingContract: forwarderAddress,
  }

  const types = {
    ForwardRequest: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'gas', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint48' },
      { name: 'data', type: 'bytes' },
    ],
  }

  const message = {
    from: getAddress(from),
    to: getAddress(target),
    value,
    gas,
    nonce,
    deadline: deadline as number,
    data,
  }

  const signature = await walletClient.signTypedData({
    account: walletClient.account!,
    domain,
    types,
    primaryType: 'ForwardRequest',
    message,
  })

  return {
    from: getAddress(from),
    to: getAddress(target),
    value,
    gas,
    deadline: deadline as number,
    data,
    signature,
  }
}

/**
 * Sleep for a given number of milliseconds
 * @param ms The number of milliseconds to sleep
 * @returns A promise that resolves after the specified time
 */
export async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
