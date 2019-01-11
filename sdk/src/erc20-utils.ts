import { BigNumber } from 'bignumber.js'
import { IERC20Token as TokenType } from 'types/IERC20Token'
import { sendTransaction } from './contract-utils'

const GOLD_TOKEN_ADDRESS = '0x000000000000000000000000000000000000ce10'

export async function getErc20Balance(contract: TokenType, address: string, web3: any) {
  const balance = await balanceOf(contract, address, web3)
  // TODO(asa): Add decimals to IERC20Token interface
  // @ts-ignore
  const decimals = await contract.methods.decimals().call()
  // @ts-ignore
  const one = new BigNumber(10).pow(decimals)
  return new BigNumber(balance).div(one)
}

// TODO(asa): Figure out why GoldToken.balanceOf() returns 2^256 - 1
export async function balanceOf(contract: TokenType, address: string, web3: any) {
  if (contract.options.address === GOLD_TOKEN_ADDRESS) {
    return new BigNumber(await web3.eth.getBalance(address))
  } else {
    return new BigNumber(await contract.methods.balanceOf(address).call())
  }
}

export async function convertToContractDecimals(value: number | BigNumber, contract: TokenType) {
  // @ts-ignore
  const decimals = new BigNumber(await contract.methods.decimals().call())
  const one = new BigNumber(10).pow(decimals.toNumber())
  return one.times(value)
}

export async function parseFromContractDecimals(value: BigNumber, contract: TokenType) {
  // @ts-ignore
  const decimals = new BigNumber(await contract.methods.decimals().call())
  const one = new BigNumber(10).pow(decimals.toNumber())
  return value.div(one)
}

export async function selectTokenContractByIdentifier(contracts: TokenType[], identifier: string) {
  const identifiers = await Promise.all(
    // @ts-ignore
    contracts.map((contract) => contract.methods.symbol().call())
  )
  const index = identifiers.indexOf(identifier)
  return contracts[index]
}

export async function approveToken(
  token: TokenType,
  address: string,
  approveAmount: BigNumber,
  txOptions = {}
) {
  return await sendTransaction(token.methods.approve(address, approveAmount.toString()), txOptions)
}
