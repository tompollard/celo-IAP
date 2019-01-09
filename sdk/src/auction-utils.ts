import { BigNumber } from 'bignumber.js'
import { BSTAuction as AuctionType } from 'types/BSTAuction'
import { IERC20Token as TokenType } from 'types/IERC20Token'
import { GoldToken as GoldTokenType } from 'types/GoldToken'
import { StableToken as StableTokenType } from 'types/StableToken'
import { sendTransaction } from './contract-utils'
import { approveToken } from './erc20-utils'
// Write out the full number in "toString()"
BigNumber.config({ EXPONENTIAL_AT: 1e9 })

export function parseAuctionParams(auctionParams: any) {
  return {
    stage: new BigNumber(auctionParams[0]).toNumber(),
    cappedToken: auctionParams[1],
    cap: new BigNumber(auctionParams[2]),
    stageDuration: new BigNumber(auctionParams[3]),
    startTime: new BigNumber(auctionParams[4]),
    nonce: new BigNumber(auctionParams[5]),
  }
}

export function parseBidParams(bidParams: any) {
  return {
    state: new BigNumber(bidParams[0]).toNumber(),
    bidId: new BigNumber(bidParams[1]),
    bidHash: bidParams[2],
    committedSellTokenAmount: new BigNumber(bidParams[3]),
  }
}
export const StagesEnum = {
  Reset: 0,
  Commit: 1,
  Reveal: 2,
  Fill: 3,
  Ended: 4,
}

export function stageStartTime(stage: number, auctionParams: any) {
  const offset = auctionParams.stageDuration.times(stage - 1)
  return auctionParams.startTime.plus(offset)
}

export function auctionInProgress(stage: number) {
  return !(stage == StagesEnum.Ended || stage == StagesEnum.Reset)
}

export function stageName(stage: number) {
  return Object.keys(StagesEnum)[stage]
}

export async function findAuctionInProgress(
  stableToken: StableTokenType,
  goldToken: GoldTokenType,
  auction: AuctionType
) {
  const expansionAuctionParams = parseAuctionParams(
    await auction.methods
      // @ts-ignore Only the newest auction has this, causing tsc to complain.
      .getAuctionParams(goldToken.options.address, stableToken.options.address)
      .call()
  )
  const contractionAuctionParams = parseAuctionParams(
    await auction.methods
      // @ts-ignore Only the newest auction has this, causing tsc to complain.
      .getAuctionParams(stableToken.options.address, goldToken.options.address)
      .call()
  )

  if (auctionInProgress(expansionAuctionParams.stage)) {
    return {
      sellToken: goldToken,
      buyToken: stableToken,
      params: expansionAuctionParams,
    }
  } else if (auctionInProgress(contractionAuctionParams.stage)) {
    return {
      sellToken: stableToken,
      buyToken: goldToken,
      params: contractionAuctionParams,
    }
  } else {
    return null
  }
}

export function getBidHash(
  sellTokenAmount: BigNumber,
  buyTokenAmount: BigNumber,
  salt: BigNumber,
  nonce: BigNumber,
  web3: any
) {
  return web3.utils.soliditySha3(
    { type: 'uint256', value: sellTokenAmount },
    { type: 'uint256', value: buyTokenAmount },
    { type: 'uint256', value: salt },
    { type: 'uint256', value: nonce }
  )
}

export async function getBidIndex(
  auction: AuctionType,
  sellTokenAddress: string,
  buyTokenAddress: string,
  account: string,
  bidHash: string
) {
  const numBids = await auction.methods
    .getNumBids(sellTokenAddress, buyTokenAddress, account)
    .call()
  for (let i = 0; i < parseInt(numBids); i++) {
    const bid = parseBidParams(
      await auction.methods.getBidParams(sellTokenAddress, buyTokenAddress, account, i).call()
    )
    if (bid.bidHash === bidHash) {
      return i
    }
  }
  throw new Error(`Unable to find a bid with hash ${bidHash} for account ${account}`)
}

export async function commitBid(
  auction: AuctionType,
  nonce: BigNumber,
  sellToken: TokenType,
  buyToken: TokenType,
  sellTokenAmount: BigNumber,
  buyTokenAmount: BigNumber,
  web3: any
) {
  const salt = web3.utils.randomHex(32)
  const bidHash = getBidHash(sellTokenAmount, buyTokenAmount, salt, nonce, web3)
  await approveToken(sellToken, auction.options.address, sellTokenAmount)
  await sendTransaction(
    auction.methods.commit(
      sellToken.options.address,
      buyToken.options.address,
      // @ts-ignore
      sellTokenAmount,
      bidHash
    )
  )
  return salt
}

export async function revealBid(
  auction: AuctionType,
  sellTokenAddress: string,
  buyTokenAddress: string,
  sellTokenAmount: BigNumber,
  buyTokenAmount: BigNumber,
  salt: BigNumber,
  nonce: BigNumber,
  account: string,
  web3: any
) {
  const bidHash = getBidHash(sellTokenAmount, buyTokenAmount, salt, nonce, web3)
  const bidIndex = await getBidIndex(auction, sellTokenAddress, buyTokenAddress, account, bidHash)
  return await sendTransaction(
    auction.methods.reveal(
      sellTokenAddress,
      buyTokenAddress,
      // @ts-ignore
      salt,
      sellTokenAmount,
      buyTokenAmount,
      bidIndex
    )
  )
}

export async function fillBid(
  auction: AuctionType,
  sellTokenAddress: string,
  buyTokenAddress: string,
  bidIndex: number
) {
  return await sendTransaction(auction.methods.fill(sellTokenAddress, buyTokenAddress, bidIndex))
}

export async function withdraw(auction: AuctionType, tokenAddress: string, account: string) {
  const pendingWithdrawals = await auction.methods.pendingWithdrawals(tokenAddress, account).call()
  if (Number(pendingWithdrawals) > 0) {
    await sendTransaction(auction.methods.withdraw(tokenAddress))
  }
  return pendingWithdrawals
}

export async function sleepUntilStage(stage: number, auctionParams: any) {
  const stageTime = await stageStartTime(stage, auctionParams)
  const sleep = require('util').promisify(setTimeout)
  const now = new BigNumber(Date.now())
  // We add an extra 10 seconds to be safe.
  const sleepTime = stageTime
    .times(1000)
    .minus(now)
    .plus(10000)
  await sleep(sleepTime)
}

// TODO(asa): This function is currently untested and should be deleted if not useful.
// Committing this so others can re-use parts they deem useful.
export async function executeBid(
  auction: AuctionType,
  sellToken: TokenType,
  buyToken: TokenType,
  sellTokenAmount: BigNumber,
  buyTokenAmount: BigNumber,
  account: string,
  web3: any
) {
  const auctionParams = parseAuctionParams(
    await await auction.methods
      // @ts-ignore Only the newest auction has this, causing tsc to complain.
      .getAuctionParams(sellToken.options.address, buyToken.options.address)
      .call()
  )
  const salt = await commitBid(
    auction,
    auctionParams.nonce,
    sellToken,
    buyToken,
    sellTokenAmount,
    buyTokenAmount,
    web3
  )

  await sleepUntilStage(StagesEnum.Reveal, auctionParams)
  await revealBid(
    auction,
    sellToken.options.address,
    buyToken.options.address,
    sellTokenAmount,
    buyTokenAmount,
    salt,
    auctionParams.nonce,
    account,
    web3
  )

  await sleepUntilStage(StagesEnum.Fill, auctionParams)
  // TODO(asa): Dedup code here.
  const bidHash = getBidHash(sellTokenAmount, buyTokenAmount, salt, auctionParams.nonce, web3)
  const bidIndex = await getBidIndex(
    auction,
    sellToken.options.address,
    buyToken.options.address,
    account,
    bidHash
  )
  await fillBid(auction, sellToken.options.address, buyToken.options.address, bidIndex)
  return await Promise.all([
    withdraw(auction, sellToken.options.address, account),
    withdraw(auction, sellToken.options.address, account),
  ])
}
