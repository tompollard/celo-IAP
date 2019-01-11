# Celo SDK
The Celo SDK contains libraries useful for interacting with the Celo blockchain and smart contracts.

## Build
You can build the sdk by running
```
yarn && yarn run build
```

This will download the latest smart contract [ABIs](https://solidity.readthedocs.io/en/develop/abi-spec.html), build getters for the [web3 Contract objects](https://web3js.readthedocs.io/en/1.0/web3-eth-contract.html) used to interact with the smart contracts, and generate type definitions using [Typechain](https://github.com/ethereum-ts/TypeChain).
