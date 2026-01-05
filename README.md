# Radrum Vault Smart Contract

A sophisticated yield-bearing vault for Stacks, featuring dynamic strategy allocation, risk-adjusted optimization, gamification, and advanced governance.

---

## Features

- **Multi-Strategy Yield Vault:**  
  Supports multiple strategies (e.g., lending, liquidity pools) with dynamic allocation.

- **Risk Management:**  
  Tracks APY, volatility, drawdown, and Sharpe ratio for each strategy. Owner can optimize allocations based on risk metrics.

- **Dynamic Allocation & Auto-Rebalancing:**  
  Automatically rebalances strategies when allocations drift beyond a threshold.

- **Fee Structure:**  
  Management and performance fees, with high-water mark tracking.  
  **Now includes:** Owner can update both management and performance fees, and set the treasury address.

- **Gamification:**  
  Loyalty bonuses, referral codes, and points system (fungible token).  
  **Now includes:** Users can claim loyalty bonuses, and the owner can manually award referral points.

- **Governance:**  
  Owner can update allocations, fees, treasury, pause/unpause, transfer ownership, and accept ownership.  
  **Now includes:** Two-step ownership transfer (initiate and accept).

- **User Interactions:**  
  Deposit, request withdrawal (with cooldown), execute withdrawal, claim loyalty bonus, and view stats.

---

## Data Structures

- **Globals:**  
  Tracks assets, shares, fees, owner, paused/emergency state, allocations, and gamification status.

- **Maps:**  
  - `shares`: User balances and deposit history  
  - `strategies`: Strategy info and risk metrics  
  - `strategy-allocations`: Target/current weights  
  - `strategy-risk-limits`: Risk limits per strategy  
  - `user-achievements`: Points, level, referrals, loyalty  
  - `user-referrals`: Referral stats  
  - `referral-codes`: Code ownership and usage  
  - `withdrawal-requests`: Pending withdrawals  
  - `performance-history`: Historical metrics

---

## Main Functions

### Initialization

- `initialize`: Sets up strategies, allocations, and risk limits.

### User Actions

- `deposit(amount, min-shares, referral-code)`: Deposit STX, receive shares, earn points, and trigger auto-rebalance if needed.
- `request-withdrawal(user-shares)`: Request withdrawal (24h cooldown).
- `execute-withdrawal`: Withdraw STX after cooldown.
- `claim-loyalty-bonus`: Update loyalty multiplier and claim bonus.
- `get-user-stats(user)`: View user stats, including shares, achievements, loyalty multiplier, and referrals.

### Strategy & Yield

- `simulate-yield(strategy-id, amount)`: Owner simulates yield for a strategy.
- `harvest-all-strategies`: Collect yield and performance fees, auto-rebalance if needed.

### Allocation & Risk

- `rebalance-strategies`: Withdraw and redeploy assets according to target weights.
- `update-strategy-risk-metrics`: Owner updates APY, volatility, drawdown.
- `optimize-allocation-by-sharpe`: Set allocations based on Sharpe ratios.

### Governance

- `set-strategy-allocation`: Update target weight and max allocation.
- `toggle-auto-rebalance`: Enable/disable auto-rebalancing.
- `set-rebalance-threshold`: Set drift threshold.
- `pause-vault` / `unpause-vault` / `emergency-shutdown`: Pause or shut down vault.
- `set-management-fee` / `set-performance-fee`: Update management and performance fees.
- `set-treasury`: Set treasury address.
- `transfer-ownership` / `accept-ownership`: Two-step ownership transfer.

### Gamification

- `create-referral-code(code)`: Create a referral code.
- `manual-award-referral-points(referrer, amount)`: Owner awards referral points.
- `claim-loyalty-bonus`: Users can claim their loyalty multiplier as a bonus.

---

## Events

Prints events for deposits, withdrawals, rebalances, fee updates, strategy changes, gamification actions, loyalty bonus claims, manual referral point awards, and governance changes (including ownership transfer steps).

---

## Usage Notes

- Only the owner can initialize, update risk metrics, optimize allocations, manage governance, and manually award referral points.
- Deposits and withdrawals are subject to cooldowns, fees, and rebalancing logic.
- Loyalty and referral bonuses are tracked and can be claimed by users.
- Ownership transfer is now a two-step process for added security.

---

## License

MIT (or specify your license)

---

## Disclaimer

This contract is for educational and experimental purposes. Use at your own risk. Review and audit before deploying to mainnet.
