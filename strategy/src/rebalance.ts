import BSTAuction from '@celo/sdk/dist/contracts/BSTAuction'
import Exchange from '@celo/sdk/dist/contracts/Exchange'
import GoldToken from '@celo/sdk/dist/contracts/GoldToken'
import StableToken from '@celo/sdk/dist/contracts/StableToken'
import { unlockAccount } from '@celo/sdk/dist/src/account-utils'
import { portfolioWeights, rebalancePortfolio } from '@celo/sdk/dist/src/exchange-utils'
import { BigNumber } from 'bignumber.js'
import Web3 = require('web3')

// Attempt to always have 50% cUSD 50% cGLD
const TARGET_WEIGHT = 0.5
const FOUR_WEEKS = 4 * 7 * 24 * 3600

const rebalance = async () => {
  const argv = require('minimist')(process.argv.slice(2), {
    string: ['host'],
    default: { host: 'localhost', noUnlock: true },
  })
  // @ts-ignore
  const web3: Web3 = new Web3(`ws://${argv.host}:8546`)
  const exchange = await Exchange(web3)
  const auction = await BSTAuction(web3)
  const stableToken = await StableToken(web3)
  const goldToken = await GoldToken(web3)

  let account: string
  if (!argv.noUnlock) {
    // TODO(asa): Don't unlock when already unlocked, won't work with the miner as is
    account = await unlockAccount(web3, FOUR_WEEKS) // Unlock for 4 weeks so our strategy can run.
  } else {
    const accounts = await web3.eth.getAccounts()
    account = accounts[0]
  }

  const shouldRebalance = async (targetWeight: BigNumber, currentWeight: BigNumber) => {
    return currentWeight
      .minus(targetWeight)
      .abs()
      .isGreaterThan(0.05)
  }

  const rebalanceIfNecessary = async (targetStableTokenWeight: BigNumber) => {
    if (targetStableTokenWeight.isGreaterThan(1) || targetStableTokenWeight.isLessThan(0)) {
      throw new Error('Target cUSD allocation must be less than 1 and greater than 0')
    }
    const [stableTokenWeight] = await portfolioWeights(
      exchange,
      stableToken,
      goldToken,
      account,
      web3
    )
    if (shouldRebalance(targetStableTokenWeight, stableTokenWeight)) {
      console.log(
        `Current portfolio weight in cUSD is ${stableTokenWeight.toString()}, rebalancing to ${targetStableTokenWeight.toString()}`
      )
      await rebalancePortfolio(
        exchange,
        stableToken,
        goldToken,
        targetStableTokenWeight,
        targetStableTokenWeight.minus(1).abs(),
        account,
        web3
      )
    } else {
      console.log(
        `Current portfolio weight in cUSD is ${stableTokenWeight.toString()} and target is ${targetStableTokenWeight.toString()}, not rebalancing.`
      )
    }
  }

  const targetWeight = new BigNumber(TARGET_WEIGHT)

  // Consider rebalancing every time we withdraw tokens from the auction or someone other than us
  // trades on the exchange.
  auction.events.Withdrawal({ filter: { bidder: account } }).on('data', async (_: any) => {
    console.log('We withdrew from the auction, considering rebalancing')
    await rebalanceIfNecessary(targetWeight)
  })

  exchange.events.Exchange().on('data', async (event: any) => {
    if (event.returnValues.exchanger.toLowerCase() != account.toLowerCase()) {
      console.log('Someone else traded on the exchange, considering rebalancing')
      await rebalanceIfNecessary(targetWeight)
    }
  })
}

rebalance()
