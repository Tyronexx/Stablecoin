## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

<!-- Stable coin architecture -->
Our stable coin is
1. (Ralative stability) Anchored or Pegged to USD (Our stable coin is always worth 1 dollar)
   1. We'll use chainlink price feed
   2. Set a function to exchange ETH & BTC -> $$ equivalent
2. Stability Mechanism (Minting): Algorithmic (Decentralized) (No centralized entitiy will mint/burn)
   1. People can only mint the stablecoin with enough collateral
3. Collateral: Exogenous (Crypto collateral: wETH & wBTC (ERC20 version of ETH & BTC))


tldr: Users can mint DSC up to 50% of their collateral value, i.e., a 2:1 collateral-to-debt ratio.

If a user has $1,000 worth of collateral, they can mint a maximum of $500 DSC.

If they mint more than $500, they’d be under-collateralized, breaking the health factor.


Invariant is a property or condition of the system that should always remain true, regardless of the sequence of valid operations performed.