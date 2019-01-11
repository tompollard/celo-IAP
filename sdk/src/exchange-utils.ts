import { BigNumber } from 'bignumber.js'
import { Exchange as ExchangeType } from 'types/Exchange'
import { IERC20Token as TokenType } from 'types/IERC20Token'
import { sendTransaction } from './contract-utils'
import { approveToken, balanceOf } from './erc20-utils'
// Write out the full number in "toString()"
BigNumber.config({ EXPONENTIAL_AT: 1e9 })

export async function exchangePrice(
  exchange: ExchangeType,
  sellToken: TokenType,
  buyToken: TokenType
) {
  const price = await exchange.methods
    .getTokenPrice(sellToken.options.address, buyToken.options.address)
    .call()
  return new BigNumber(price[0]).div(price[1])
}

export async function getBuyTokenAmount(
  exchange: ExchangeType,
  sellToken: TokenType,
  buyToken: TokenType,
  sellTokenAmount: BigNumber
) {
  return exchange.methods
    .getBuyTokenAmount(
      sellToken.options.address,
      buyToken.options.address,
      sellTokenAmount.toString()
    )
    .call()
}

export async function getSellTokenAmount(
  exchange: ExchangeType,
  sellToken: TokenType,
  buyToken: TokenType,
  buyTokenAmount: BigNumber
) {
  return exchange.methods
    .getSellTokenAmount(
      sellToken.options.address,
      buyToken.options.address,
      buyTokenAmount.toString()
    )
    .call()
}

export async function portfolioWeights(
  exchange: ExchangeType,
  tokenA: TokenType,
  tokenB: TokenType,
  account: string,
  web3: any
) {
  const tokenABalance = await balanceOf(tokenA, account, web3)
  const tokenBBalance = await balanceOf(tokenB, account, web3)
  const price = await exchangePrice(exchange, tokenA, tokenB)
  const tokenBBalanceInTokenA = tokenBBalance.times(price)
  const totalValueInTokenA = tokenABalance.plus(tokenBBalanceInTokenA).decimalPlaces(0)
  const tokenAWeight = tokenABalance.div(totalValueInTokenA)
  return [tokenAWeight, tokenAWeight.minus(1).abs()]
}

export async function rebalancePortfolio(
  exchange: ExchangeType,
  tokenA: TokenType,
  tokenB: TokenType,
  tokenAWeight: BigNumber,
  tokenBWeight: BigNumber,
  account: string,
  web3: any
) {
  if (tokenAWeight.plus(tokenBWeight).toNumber() != 1) {
    throw new Error('Portfolio weights must sum to 1')
  }
  const tokenABalance = await balanceOf(tokenA, account, web3)
  const tokenBBalance = await balanceOf(tokenB, account, web3)
  const price = await exchangePrice(exchange, tokenA, tokenB)
  const totalValueInTokenA = tokenABalance.plus(tokenBBalance.times(price)).decimalPlaces(0)
  const targetTokenABalance = totalValueInTokenA.times(tokenAWeight).decimalPlaces(0)
  const targetTokenBBalance = totalValueInTokenA
    .minus(targetTokenABalance)
    .div(price)
    .decimalPlaces(0)

  let sellToken: TokenType
  let buyToken: TokenType
  let sellTokenAmount: BigNumber
  if (tokenABalance.isGreaterThan(targetTokenABalance)) {
    sellTokenAmount = tokenABalance.minus(targetTokenABalance)
    sellToken = tokenA
    buyToken = tokenB
  } else if (tokenBBalance.isGreaterThan(targetTokenBBalance)) {
    sellTokenAmount = tokenBBalance.minus(targetTokenBBalance)
    sellToken = tokenB
    buyToken = tokenA
  } else {
    return
  }
  await approveToken(sellToken, exchange.options.address, sellTokenAmount)
  // TODO(asa): Limit slippage.
  await exchangeToken(
    exchange,
    sellToken.options.address,
    buyToken.options.address,
    sellTokenAmount,
    new BigNumber(0)
  )
}

export async function exchangeToken(
  exchange: ExchangeType,
  sellTokenAddress: string,
  buyTokenAddress: string,
  sellTokenAmount: BigNumber,
  minBuyTokenAmount: BigNumber,
  txOptions = {}
) {
  return await sendTransaction(
    exchange.methods.exchange(
      sellTokenAddress,
      buyTokenAddress,
      sellTokenAmount.toString(),
      minBuyTokenAmount.toString()
    ),
    txOptions
  )
}
