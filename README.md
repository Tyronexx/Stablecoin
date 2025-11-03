# 🪙 Decentralized Stablecoin System (DSC)

A **fully on-chain**, **exogenously collateralized**, and **algorithmically stabilized** stablecoin protocol built in Solidity.  
This system is composed of two core contracts:  
- `DecentralizedStableCoin.sol` — ERC20 stablecoin implementation  
- `DSCEngine.sol` — Core logic engine that governs minting, burning, collateral management, and peg stability  

---

## ⚙️ Overview

The **Decentralized Stablecoin System (DSC)** is a crypto-backed, overcollateralized stablecoin protocol inspired by MakerDAO’s DAI but designed for simplicity, transparency, and extensibility.

It maintains a soft peg to a target value (e.g. 1 USD) using **exogenous collateral** such as **ETH** and **BTC**, combined with an **algorithmic stability mechanism** governed by `DSCEngine`.

## 🪄 Core Components

### 1. **DecentralizedStableCoin.sol**
> The ERC20 implementation of the stablecoin (`DSC`), fully controlled by the `DSCEngine`.

| Function | Description |
|-----------|-------------|
| `mint(address _to, uint256 _amount)` | Mints DSC to `_to`. Only callable by DSCEngine (owner). |
| `burn(uint256 _amount)` | Burns DSC from caller’s balance to maintain peg. Only callable by DSCEngine. |
| `balanceOf(address)` | Returns account balance. |
| `transfer(address to, uint256 amount)` | Standard ERC20 transfer. |

🔒 **Safety rules**
- Only DSCEngine can mint/burn.  
- Zero-address mints not allowed.  
- Burn/mint amount must be > 0.  
- Burn amount ≤ user balance.  

---

### 2. **DSCEngine.sol**
> The protocol’s logic layer — manages collateral, user positions, and stability mechanisms.

| Feature | Description |
|----------|-------------|
| **Collateral Management** | Accepts ETH & BTC (via wrapped tokens) as deposits. Tracks and values collateral. |
| **Minting Control** | Users can mint DSC up to a defined collateral ratio. Prevents overleveraging. |
| **Health Factor Calculation** | Continuously monitors account solvency via a health factor formula. |
| **Liquidations** | Incentivizes third parties to liquidate unsafe positions to maintain solvency. |
| **Redeem & Withdraw** | Allows users to burn DSC and redeem collateral proportionally. |
| **Price Feeds** | Uses Chainlink oracles for reliable on-chain pricing of collateral assets. |

---

## 🧮 Stability Logic

1. **Collateral Deposit:**  
   Users lock ETH or BTC as collateral via `depositCollateral()` in DSCEngine.

2. **Minting:**  
   DSCEngine mints DSC (up to a safe collateral ratio) by calling `DecentralizedStableCoin.mint()`.

3. **Burning / Repayment:**  
   Users repay their DSC debt using `burnDSC()`; DSCEngine then unlocks collateral.

4. **Health Factor Monitoring:**  
   The engine checks user solvency (`healthFactor >= 1`).  
   If below threshold → liquidation is triggered.

5. **Liquidation:**  
   Third parties repay DSC debt of unhealthy accounts and receive discounted collateral.

---

## 🧱 Key Functions (DSCEngine)

| Function | Purpose |
|-----------|----------|
| `depositCollateral(address token, uint256 amount)` | Deposit supported collateral. |
| `mintDSC(uint256 amountDSC)` | Mint DSC tokens against your collateral. |
| `redeemCollateral(address token, uint256 amount)` | Withdraw collateral by burning DSC. |
| `liquidate(address user, address collateralToken, uint256 debtToCover)` | Liquidate undercollateralized positions. |
| `getHealthFactor(address user)` | Returns the solvency score of a position. |
| `getCollateralValue(address user)` | Returns the total USD value of a user’s collateral. |

---

## 🧰 Tech Stack

- **Solidity:** ^0.8.18  
- **Frameworks:** Foundry / Hardhat  
- **Libraries:**  
  - OpenZeppelin (`ERC20`, `Ownable`, `ERC20Burnable`)  
  - Chainlink Price Feeds  
- **License:** MIT  

---

## 🧪 Example Flow

1. User deposits 1 ETH into DSCEngine.  
2. DSCEngine reads ETH/USD price via Chainlink.  
3. Based on collateral ratio (e.g. 150%), user can mint up to $1000 DSC if 1 ETH = $1500.  
4. If ETH price drops → health factor falls.  
5. Below threshold, position is open for liquidation.  
6. Liquidator repays DSC and claims collateral with a small bonus.

---

## 🔐 Security Considerations

- Overcollateralization protects against price volatility.  
- Chainlink price feeds ensure reliable on-chain valuations.  
- DSCEngine is the **sole authority** for mint/burn operations.  
- No admin functions — decentralized by code.  
- MIT-licensed and open for community audits.

---

## 🚀 Deployment & Usage

```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Build and test
forge build
forge test

# Deploy contracts
forge script script/DeployDSC.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>



✍️ Author

Richard Ikenna
Smart Contract Engineer • Solidity Developer
Focused on building transparent, decentralized financial primitives.