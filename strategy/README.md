# Example strategies
This package contains some example automated trading strategies that can be used as a template for building more sophisticated strategies.

## Build
Run `yarn`

## Rebalancing
Once celo core is running, you can execute a simple strategy by running
```
yarn run rebalance
```

This strategy listens to the blockchain for trades on the exchange made by others that would move the cUSD/cGLD price, as well as auction proceed withdrawals made by you that would adjust your balances. If your portfolio cUSD/cGLD weights deviate sufficiently from the target weights, it will then execute a trade on the exchange to bring them back in line with the target.
