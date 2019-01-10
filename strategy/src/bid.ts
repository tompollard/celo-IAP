import * as _ from 'lodash'
import Web3 = require('web3')


import BSTAuction from '@celo/sdk/dist/contracts/BSTAuction'
import Exchange from '@celo/sdk/dist/contracts/Exchange'
import GoldToken from '@celo/sdk/dist/contracts/GoldToken'
import StableToken from '@celo/sdk/dist/contracts/StableToken'
import { unlockAccount } from '@celo/sdk/dist/src/account-utils'
import { executeBid } from '@celo/sdk/dist/src/auction-utils'
import { selectContractByAddress } from '@celo/sdk/dist/src/contract-utils'
import { exchangePrice } from '@celo/sdk/dist/src/exchange-utils'
import { balanceOf } from '@celo/sdk/dist/src/erc20-utils'
import { Exchange as ExchangeType } from '@celo/sdk/types/Exchange'

// Strategy parameters (feel free to play around with these)
const bidDiscount = 1.1 // The 'discount' we bid at (1.1 = 10%)
const balanceProportionToBid = 0.9 // The proportion of our valance we bid
const randomFactor = (Math.random() * .001) - 0.0005  // a random 'jitter' to make a bid easy to identify

// Additional parameters for multiBidStrategy
const numBids = 5       // The number of bids to make, centered around bidDiscount
const bidRange = 0.1    // Spread of bids
const FOUR_WEEKS = 4 * 7 * 24 * 3600

// This implements a simple auction strategy. We bid 90% of our balance in the auction and
// ask for tokens such that we get a 10% discount relative to the current price quoted
// on the exchange.
const simpleBidStrategy = async (web3: any) => {

  // Initialize contract objects
  const exchange: ExchangeType = await Exchange(web3)
  const auction = await BSTAuction(web3)
  const stableToken = await StableToken(web3)
  const goldToken = await GoldToken(web3)
  const account = await unlockAccount(web3, FOUR_WEEKS) // Unlock for 4 weeks so our strategy can run.

  auction.events.AuctionStarted().on('data', async (event: any) => {
    const sellToken = selectContractByAddress(
      [stableToken, goldToken],
      event.returnValues.sellToken
    )
    const buyToken = selectContractByAddress(
      [stableToken, goldToken],
      event.returnValues.buyToken
    )

    const sellTokenBalance = await balanceOf(sellToken, account, web3)
    const sellTokenAmount = sellTokenBalance
      .times(balanceProportionToBid)
      .decimalPlaces(0)
    
    const bidAdjustment = bidDiscount + randomFactor

    const price = await exchangePrice(exchange, buyToken, sellToken)
    const buyTokenAmount = sellTokenAmount
      .times(price)
      .times(bidAdjustment)
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
    console.info(`Bid successfully executed!\n Sell Token Amount Withdrawn: ${auctionSellTokenWithdrawn}\n Buy Token Amount Withdrawn: ${auctionBuyTokenWithdrawn}`)
  })
}

const multiBidStrategy = async (web3: any) => {

  const exchange: ExchangeType = await Exchange(web3)
  const auction = await BSTAuction(web3)
  const stableToken = await StableToken(web3)
  const goldToken = await GoldToken(web3)
  const account = await unlockAccount(web3, FOUR_WEEKS) // Unlock for 4 weeks so our strategy can run.

  auction.events.AuctionStarted().on('data', async (event: any) => {
    const sellToken = selectContractByAddress(
      [stableToken, goldToken],
      event.returnValues.sellToken
    )
    const buyToken = selectContractByAddress(
      [stableToken, goldToken],
      event.returnValues.buyToken
    )

    const sellTokenBalance = await balanceOf(sellToken, account, web3)
    const sellTokenAmount = sellTokenBalance
      .times(balanceProportionToBid)
      .times(1.0/numBids)
      .decimalPlaces(0)

    const price = await exchangePrice(exchange, buyToken, sellToken)

    const buyTokenDeltas = _.range(
      bidDiscount - bidRange,
      bidDiscount + bidRange,
      bidRange / numBids
    )
    
    buyTokenDeltas.forEach( async(delta) => {
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
      console.info(`Bid successfully executed!\n Sell Token Amount Withdrawn: ${auctionSellTokenWithdrawn}\n Buy Token Amount Withdrawn: ${auctionBuyTokenWithdrawn}`)
    });

  })
}

const bid = async () => {
  const argv = require('minimist')(process.argv.slice(2), {
    string: ['host'],
    default: { host: 'localhost', noUnlock: true },
  })
  // @ts-ignore
  const web3: Web3 = new Web3(`ws://${argv.host}:8546`)
  if (process.argv[2] == 'multi') {
    multiBidStrategy(web3)
  }
  else if (process.argv[2] == 'simple') {
    simpleBidStrategy(web3)
  }
  else {
    throw new Error('please specify which strategy to run: simple or multi')
  }
}

bid()

