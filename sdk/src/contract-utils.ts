import { Transaction, Contract } from 'web3/types'
import { omitBy } from 'lodash'
import Web3 = require('web3')

export function selectContractByAddress(contracts: Contract[], address: string) {
  const addresses = contracts.map((contract) => contract.options.address)
  const index = addresses.indexOf(address)
  if (index < 0) {
    return null
  }
  return contracts[index]
}

export function getFunctionSignatureToAbiMap(contract: any, web3: Web3.default) {
  return contract.options.jsonInterface
    .filter((functionAbi: any) => functionAbi.type == 'function')
    .reduce((map: any, functionAbi: any) => {
      map[web3.eth.abi.encodeFunctionSignature(functionAbi)] = functionAbi
      return map
    }, {})
}

export function removeNonParameters(parameters: any) {
  const integerPattern = new RegExp(/^\d/)
  return omitBy(
    parameters,
    (_value: string, key: string) =>
      integerPattern.test(key) || key === '__length__' || key === 'transactionId'
  )
}

export function parseFunctionCall(
  transaction: Transaction,
  contract: Contract,
  web3: Web3.default
) {
  // As per specificaton, the first 4 bytes denote the method ID. With the leading
  // '0x' and 2 chars per byte, this gives us the first 10 chars for the functionSignature
  // https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector
  const functionSignature = transaction.input.substring(0, 10)
  const signatureToAbi = getFunctionSignatureToAbiMap(contract, web3)
  const functionAbi = signatureToAbi[functionSignature]
  if (functionAbi == null) {
    return null
  }

  const parameters = web3.eth.abi.decodeParameters(functionAbi.inputs, transaction.input.slice(10))

  return {
    name: functionAbi.name,
    parameters: removeNonParameters(parameters),
  }
}

export async function sendTransaction(tx: any, options = {}) {
  const estGas = await tx.estimateGas()
  return await tx.send({ gas: estGas * 2, ...options })
}
