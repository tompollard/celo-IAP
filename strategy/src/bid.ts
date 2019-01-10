import * as _ from 'lodash'
import { BigNumber } from 'bignumber.js'
import Web3 = require('web3')


import BSTAuction from '@celo/sdk/dist/contracts/BSTAuction'
import Exchange from '@celo/sdk/dist/contracts/Exchange'
import GoldToken from '@celo/sdk/dist/contracts/GoldToken'
import StableToken from '@celo/sdk/dist/contracts/StableToken'
import { unlockAccount } from '@celo/sdk/dist/src/account-utils'
import { executeBid, findAuctionInProgress } from '@celo/sdk/dist/src/auction-utils'
import { exchangePrice } from '@celo/sdk/dist/src/exchange-utils'
import {
  selectTokenContractByAddress,
} from '@celo/sdk/dist/src/erc20-utils'
import { Exchange as ExchangeType } from '@celo/sdk/types/Exchange'

// Strategy parameters (feel free to play around with these)
const bidAmount = 1.1
const randomFactor = (Math.random() * .001) - 0.0005

// Additional parameters for multiBidStrategy
const numBids = 5       // The number of bids to make, centered around bidAmount
const bidRange = 0.1    // Spread of bids

const simpleBidStrategy = async () => {
  // @ts-ignore
  const web3: Web3 = new Web3(`ws://${argv.host}:8546`)
  const exchange: ExchangeType = await Exchange(web3)
  const auction = await BSTAuction(web3)
  const stableToken = await StableToken(web3)
  const goldToken = await GoldToken(web3)
  const account = await unlockAccount(web3, 2419200) // Unlock for 4 weeks so our strategy can run.

  // TODO: add multiple loops

  // This implements a simple auction strategy. We bid 90% of our balance in the auction and
  // ask for tokens such that we get a 10% discount relative to the current price quoted
  // on the exchange.
  auction.events.AuctionStarted().on('data', async (event: any) => {
    const sellToken = selectTokenContractByAddress(
      [stableToken, goldToken],
      event.returnValues.sellToken
    )
    const buyToken = selectTokenContractByAddress(
      [stableToken, goldToken],
      event.returnValues.buyToken
    )

    const currentAuction = findAuctionInProgress(stableToken, goldToken, auction)
    // Aim to sell up to 90% of our sellToken balance in the auction.
    // TODO*asa): Does this work with GoldToken?
    const sellTokenBalance = new BigNumber(await currentAuction.sellToken.methods.balanceOf(account).call())
    const sellTokenAmount = sellTokenBalance.times(0.9)


    // a random 'jitter' to make a bid easy to identify
    
    const bidDiscount = bidAmount + randomFactor

    const price = await exchangePrice(exchange, buyToken, sellToken)
    const buyTokenAmount = sellTokenAmount
      .times(price)
      .times(bidDiscount)
      .decimalPlaces(0)

    // Bid on the auction
    const [auctionSellTokenWithdrawn, auctionBuyTokenWithdrawn] = await executeBid(
      auction,
      sellToken,
      buyToken,
      sellTokenAmount,
      buyTokenAmount,
      account,
      web3
    )
    console.info(auctionSellTokenWithdrawn, auctionBuyTokenWithdrawn)
  })
}

const multiBidStrategy = async () => {
  // @ts-ignore
  const web3: Web3 = new Web3(`ws://${argv.host}:8546`)
  const exchange: ExchangeType = await Exchange(web3)
  const auction = await BSTAuction(web3)
  const stableToken = await StableToken(web3)
  const goldToken = await GoldToken(web3)
  const account = await unlockAccount(web3, 2419200) // Unlock for 4 weeks so our strategy can run.

  // TODO: add multiple loops

  // This implements a simple auction strategy. We bid 90% of our balance in the auction and
  // ask for tokens such that we get a 10% discount relative to the current price quoted
  // on the exchange.
  auction.events.AuctionStarted().on('data', async (event: any) => {
    const sellToken = selectTokenContractByAddress(
      [stableToken, goldToken],
      event.returnValues.sellToken
    )
    const buyToken = selectTokenContractByAddress(
      [stableToken, goldToken],
      event.returnValues.buyToken
    )

    const currentAuction = findAuctionInProgress(stableToken, goldToken, auction)

    const sellTokenBalance = new BigNumber(await currentAuction.sellToken.methods.balanceOf(account).call())
    const sellTokenAmount = sellTokenBalance.times(0.9).times(1.0/numBids)

    const price = await exchangePrice(exchange, buyToken, sellToken)

    const buyTokenDeltas = _.range(
      bidAmount - bidRange,
      bidAmount + bidRange,
      bidRange / numBids
    )
    
    buyTokenDeltas.forEach(delta => {
      const buyTokenAmount = sellTokenAmount
        .times(price)
        .times(delta + randomFactor)
        .decimalPlaces(0)

      // Bid on the auction
      const [auctionSellTokenWithdrawn, auctionBuyTokenWithdrawn] = await executeBid(
        auction,
        sellToken,
        buyToken,
        sellTokenAmount,
        buyTokenAmount,
        account,
        web3
      )
      console.info(auctionSellTokenWithdrawn, auctionBuyTokenWithdrawn)
    });

    // a random 'jitter' to make a bid easy to identify
  })
}

function bid() {
  if (process.argv[0] == 'multi') {
    multiBidStrategy()
  }
  else if (process.argv[0] == 'simple') {
    simpleBidStrategy()
  }
  else {
    console.info('please specify which strategy to run: simple or multi')
  }
}

bid()

