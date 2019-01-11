# Example strategies
This package contains some example automated trading strategies that can be used as a template for building more sophisticated strategies.

## Build
Run `yarn`

## Bidding
Once celo core is running, you can execute a simple strategy by running
```
yarn run auto-bid
```

This strategy listens to the blockchain for the start of an auction. It then looks up the current price being quoted on the exchange, and bids 90% of your cUSD/cGLD balance at a 10% discount to that price, plus or minus a small random jitter.

## Rebalancing
Once celo core is running, you can execute a simple rebalancing strategy by running
```
yarn run auto-rebalance
```

This strategy listens to the blockchain for trades on the exchange made by others that would move the cUSD/cGLD price, as well as auction proceed withdrawals made by you that would adjust your balances. If your portfolio cUSD/cGLD weights deviate sufficiently from the target weights, it will then execute a trade on the exchange to bring them back in line with the target.
