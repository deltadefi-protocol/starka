# Technical Specification: Spot Trading Vault with Performance Fee

**Share-Based NAV Accounting | USDC + ADA | 10% Fee via Share Minting**

Version 1.0 — February 2026
*For: Aiken Smart Contract & Backend Implementation*

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Core Calculation Formulas](#2-core-calculation-formulas)
3. [Deposit Operation](#3-deposit-operation)
4. [Withdrawal Operation (with Performance Fee)](#4-withdrawal-operation-with-performance-fee)
5. [Spot Trading Operations](#5-spot-trading-operations)
6. [Performance Fee Model — Share Minting](#6-performance-fee-model--share-minting)
7. [Integer Arithmetic Guidance](#7-integer-arithmetic-guidance)
8. [Implementation Responsibilities](#8-implementation-responsibilities)
9. [Edge Cases & Constraints](#9-edge-cases--constraints)
10. [Appendix: Worked Examples](#10-appendix-worked-examples)

---

## 1. System Overview

This document specifies all calculation formulas and state transitions for a Spot Trading Vault. The vault accepts USDC deposits from users, trades spot ADA tokens, and distributes gains/losses proportionally through a share-based NAV (Net Asset Value) accounting system. A 10% performance fee is collected on profitable withdrawals by minting new shares to the vault owner.

### 1.1 Architecture Summary

The vault operates as a pooled investment vehicle with the following components:

- **Vault State:** USDC balance, token holdings (ADA), total shares outstanding, depositor records
- **Depositor Record:** shares held, totalDeposited (cumulative USDC deposited, reduced proportionally on withdrawal)
- **Holdings Record:** token amount, weighted average buy price, current market price
- **Fee Model:** 10% of profit on withdrawal, collected by minting shares to vault owner (zero cost basis)

### 1.2 State Variables

| Variable | Type | Description |
|---|---|---|
| `usdcBalance` | Integer (lovelace) | Vault USDC cash balance |
| `totalShares` | Integer | Total vault shares outstanding (scaled by 10^6 for precision) |
| `holdings[symbol]` | Record | `{ amount, avgBuyPrice, currentPrice }` per token |
| `depositors[userId]` | Record | `{ shares, totalDeposited }` per depositor |
| `ownerId` | PubKeyHash | Vault operator who receives performance fee shares |
| `feeRate` | Integer | Performance fee rate (100 = 10%, denominator 1000) |
| `totalFeesCollected` | Integer | Cumulative fees collected (for reporting only) |

---

## 2. Core Calculation Formulas

### 2.1 Holdings Value

The total market value of all spot token holdings in the vault.

```
holdingsValue = SUM( holdings[i].amount * holdings[i].currentPrice )
```

*For a single-token vault (ADA only): `holdingsValue = adaAmount * adaCurrentPrice`*

### 2.2 Vault Equity (NAV)

The Net Asset Value of the vault. This is the total value backing all outstanding shares.

```
vaultEquity = usdcBalance + holdingsValue
```

### 2.3 Share Price

The price of one vault share in USDC terms. If no shares exist (genesis), the price is defined as 1.0.

```
IF totalShares == 0:
    sharePrice = 1.000000
ELSE:
    sharePrice = vaultEquity / totalShares
```

> **Implementation Note:** Use integer arithmetic with a precision scalar (e.g., 10^6) to avoid floating-point errors. All divisions should be performed last to minimize rounding loss. For Aiken, use scaled integers throughout.

### 2.4 Cost Per Share (Per Depositor)

The average cost basis per share for a specific depositor. This determines the profit threshold for fee calculation.

```
costPerShare[userId] = depositors[userId].totalDeposited / depositors[userId].shares
```

> **Critical Behavior:** Withdrawals: costPerShare stays **CONSTANT** (both shares and totalDeposited shrink by the same fraction). Deposits: costPerShare **CHANGES** (weighted average blending of existing and new entry price). This is a fundamental property of the proportional cost basis model.

### 2.5 Unrealized PnL (Per Holding)

The unrealized profit or loss on a specific token holding.

```
unrealizedPnL[symbol] = holdings[symbol].amount * (currentPrice - avgBuyPrice)
```

### 2.6 Depositor Equity

A depositor's current equity value and unrealized PnL.

```
userEquity = depositors[userId].shares * sharePrice
userPnL    = userEquity - depositors[userId].totalDeposited
```

---

## 3. Deposit Operation

A user deposits USDC into the vault and receives vault shares at the current share price.

### 3.1 Formula

```
sharePrice    = vaultEquity / totalShares    (or 1.0 if genesis)
sharesMinted  = depositAmount / sharePrice
```

### 3.2 State Transitions

| Variable | Transition |
|---|---|
| `usdcBalance` | `usdcBalance += depositAmount` |
| `totalShares` | `totalShares += sharesMinted` |
| `depositors[userId].shares` | `shares += sharesMinted` |
| `depositors[userId].totalDeposited` | `totalDeposited += depositAmount` |

### 3.3 Cost Per Share Impact

On first deposit, costPerShare equals the current sharePrice. On subsequent deposits at a different share price, costPerShare blends:

```
costPerShare_after = (totalDeposited_before + depositAmount)
                   / (shares_before + sharesMinted)
```

This is equivalent to a weighted average of the old costPerShare and the new entry sharePrice.

### 3.4 Validation Rules (Smart Contract)

1. `depositAmount > 0`
2. USDC actually transferred to vault address in the transaction
3. `sharesMinted` computed correctly (can be verified on-chain)
4. New `totalShares = old totalShares + sharesMinted`
5. Depositor record updated correctly in datum

---

## 4. Withdrawal Operation (with Performance Fee)

A user redeems vault shares for USDC. If the user is in profit, 10% of the profit is collected as a fee by minting new shares to the vault owner. If the user is at a loss, no fee is charged.

### 4.1 Full Withdrawal Formula

```
sharePrice        = vaultEquity / totalShares
grossValue        = sharesToRedeem * sharePrice
costBasisRedeemed = depositors[userId].totalDeposited     (all of it)
grossProfit       = max(0, grossValue - costBasisRedeemed)

feeAmount         = grossProfit * feeRate                 (feeRate = 0.10)
feeSharesMinted   = feeAmount / sharePrice

netPayout         = grossValue - feeAmount
netRealizedPnl    = netPayout - costBasisRedeemed
```

### 4.2 Partial Withdrawal Formula

For partial withdrawals, cost basis is reduced proportionally:

```
fractionRedeemed  = sharesToRedeem / depositors[userId].shares
costBasisRedeemed = depositors[userId].totalDeposited * fractionRedeemed

grossValue        = sharesToRedeem * sharePrice
grossProfit       = max(0, grossValue - costBasisRedeemed)

feeAmount         = grossProfit * feeRate
feeSharesMinted   = feeAmount / sharePrice
netPayout         = grossValue - feeAmount
```

### 4.3 Withdrawal by USDC Amount

When a user specifies a USDC amount to withdraw rather than a share count:

```
sharesToRedeem = desiredUsdcAmount / sharePrice
// Then apply partial withdrawal formula above
```

### 4.4 State Transitions

#### Step 1: Burn user shares

| Variable | Transition |
|---|---|
| `totalShares` | `totalShares -= sharesToRedeem` |
| `depositors[userId].shares` | `shares -= sharesToRedeem` |
| `depositors[userId].totalDeposited` | `totalDeposited -= costBasisRedeemed` |

#### Step 2: Mint fee shares to vault owner (if grossProfit > 0)

| Variable | Transition |
|---|---|
| `totalShares` | `totalShares += feeSharesMinted` |
| `depositors[ownerId].shares` | `shares += feeSharesMinted` |
| `depositors[ownerId].totalDeposited` | **NO CHANGE** (fee shares have zero cost basis) |
| `totalFeesCollected` | `totalFeesCollected += feeAmount` |

#### Step 3: Pay out USDC to user

| Variable | Transition |
|---|---|
| `usdcBalance` | `usdcBalance -= netPayout` |

> **Order of Operations:** The order matters: burn first, then mint fee shares, then deduct USDC. This ensures the share price remains consistent throughout the operation. The vault equity decreases by netPayout, but the total shares also decrease by (sharesToRedeem - feeSharesMinted), keeping the share price stable for remaining depositors.

### 4.5 Cost Per Share Behavior on Withdrawal

```
costPerShare_before = totalDeposited / shares

After partial withdrawal:
  shares_after        = shares - sharesToRedeem
  totalDeposited_after = totalDeposited - (totalDeposited * fractionRedeemed)
                       = totalDeposited * (1 - fractionRedeemed)

costPerShare_after   = totalDeposited_after / shares_after
                     = [totalDeposited * (1-f)] / [shares * (1-f)]
                     = totalDeposited / shares
                     = costPerShare_before    // UNCHANGED
```

**Proof:** Since both numerator and denominator are multiplied by the same factor (1 - fractionRedeemed), the ratio is preserved. This is why withdrawals never change cost per share.

### 4.6 Validation Rules (Smart Contract)

1. `sharesToRedeem > 0` AND `sharesToRedeem <= depositors[userId].shares`
2. `sharePrice` computed from current on-chain `vaultEquity` and `totalShares`
3. `grossProfit = max(0, grossValue - costBasisRedeemed)` (never negative)
4. `feeAmount = grossProfit * feeRate` (verify exact computation)
5. `feeSharesMinted` correctly computed and added to owner record
6. `netPayout = grossValue - feeAmount` actually sent to user
7. Sufficient USDC liquidity in vault (may require prior sell of holdings)
8. Transaction signed by depositor (userId)

---

## 5. Spot Trading Operations

Only the vault owner (operator) may execute trades. These operations change the composition of vault assets but do not change vault equity (ignoring slippage).

### 5.1 Buy Spot Token

```
totalCost = amount * pricePerToken
REQUIRE: totalCost <= usdcBalance

// Weighted average cost basis update:
existingCost       = holdings[symbol].amount * holdings[symbol].avgBuyPrice
holdings.amount   += amount
holdings.avgBuyPrice = (existingCost + totalCost) / holdings.amount
holdings.currentPrice = pricePerToken

usdcBalance -= totalCost
```

### 5.2 Sell Spot Token

```
totalProceeds = amount * pricePerToken
REQUIRE: amount <= holdings[symbol].amount

holdings[symbol].amount -= amount
holdings[symbol].currentPrice = pricePerToken
usdcBalance += totalProceeds

// avgBuyPrice remains unchanged on sell
// If holdings.amount reaches 0, remove the record
```

### 5.3 Mark-to-Market Price Update

Updates the current market price of a held token. This changes vault equity and share price without any USDC movement.

```
holdings[symbol].currentPrice = newMarketPrice
// vaultEquity and sharePrice recalculate automatically
```

> **On-Chain Consideration:** For the Aiken smart contract, mark-to-market price updates should come from a trusted oracle or be included as a redeemer parameter signed by the vault operator. The backend should validate oracle freshness before submitting transactions.

---

## 6. Performance Fee Model — Share Minting

### 6.1 Why Share Minting

Instead of deducting USDC from the withdrawal, the protocol mints new shares to the vault owner. This approach has several advantages:

- **No cash drain:** USDC stays in the vault, maintaining trading capital
- **Aligned incentives:** owner's fee is still exposed to vault performance
- **No liquidity issues:** no need to sell holdings to pay fees
- **Compounding:** fee shares grow in value as the vault performs

### 6.2 Fee Calculation Summary

```
grossProfit     = max(0, grossValue - costBasisRedeemed)
feeAmount       = grossProfit * feeRate        // feeRate = 10% = 100/1000
feeSharesMinted = feeAmount / sharePrice
netPayout       = grossValue - feeAmount

IF grossProfit == 0:  // user at loss or breakeven
    feeAmount = 0
    feeSharesMinted = 0
    netPayout = grossValue
```

### 6.3 Fee Shares Properties

| Property | Value | Rationale |
|---|---|---|
| Cost basis | 0 (zero) | Fee shares are pure profit for the owner |
| Ownership | Added to ownerId depositor record | Owner can withdraw these like any shares |
| Fee on owner withdrawal | Applied if owner withdraws at profit | Owner pays fee on their own trading profits |
| Dilution effect | All other depositors diluted equally | Withdrawal user absorbs fee via reduced payout |

### 6.4 Path Independence (Profit Case)

For profitable withdrawals, the total fee is the same regardless of withdrawal pattern:

```
Single withdrawal of $12,000 at cost basis $10,000:
  fee = ($12,000 - $10,000) * 10% = $200

Four withdrawals of $3,000 each at same share price:
  Each: fee = ($3,000 - $2,500) * 10% = $50
  Total: 4 * $50 = $200    // Same result
```

### 6.5 Loss Crystallization (Loss Case)

For partial withdrawals at a loss, crystallized losses cannot offset future gains for fee purposes:

```
User deposits $10,000. Vault drops to $0.90/share.
User withdraws $2,000 (realizes ~$222 loss).

Remaining: shares ~7,778, totalDeposited ~$7,778
costPerShare still $1.00

If vault recovers to $1.10/share:
  Remaining equity = 7,778 * 1.10 = $8,556
  Profit = $8,556 - $7,778 = $778
  Fee = $778 * 10% = $77.80

vs. staying fully invested:
  Equity = 10,000 * 1.10 = $11,000
  Profit = $11,000 - $10,000 = $1,000
  Fee = $1,000 * 10% = $100

Difference: $22.20 more fee paid due to loss crystallization
```

> **Known Tradeoff:** This is a known characteristic of the proportional cost basis model. It is simple, gas-efficient, and path-independent for profits. The alternative (high-water mark per depositor) would preserve loss offsets but adds significant on-chain complexity.

---

## 7. Integer Arithmetic Guidance

Both Aiken (on-chain) and the backend must avoid floating-point arithmetic. All values should be represented as scaled integers.

### 7.1 Recommended Precision Scalars

| Value | Scalar | Example |
|---|---|---|
| USDC amounts | 10^6 (lovelace) | 1 USDC = 1,000,000 |
| ADA amounts | 10^6 (lovelace) | 1 ADA = 1,000,000 |
| Share counts | 10^6 | 1 share = 1,000,000 units |
| Share price | 10^6 | $1.20 = 1,200,000 |
| Fee rate | 1000 | 10% = 100 |
| Cost per share | 10^6 | $1.0667 = 1,066,700 |

### 7.2 Division Order

Always multiply before dividing to preserve precision:

```
// WRONG (precision loss):
sharePrice = vaultEquity / totalShares
sharesMinted = depositAmount / sharePrice    // double division

// CORRECT (single division):
sharesMinted = (depositAmount * totalShares) / vaultEquity

// For fee calculation:
feeAmount = (grossProfit * feeRate) / FEE_DENOMINATOR
// where feeRate=100, FEE_DENOMINATOR=1000 for 10%
```

### 7.3 Rounding Policy

For all divisions that produce remainders:

- **Shares minted on deposit:** round DOWN (floor) — user receives slightly fewer shares, protects vault
- **USDC payout on withdrawal:** round DOWN (floor) — user receives slightly less, protects vault
- **Fee shares minted:** round UP (ceiling) — owner receives at least the full fee, protects owner
- **Fee amount:** round UP (ceiling) — fee is never underpaid

---

## 8. Implementation Responsibilities

### 8.1 Aiken Smart Contract (On-Chain)

The smart contract is the source of truth for fund safety. It validates that state transitions are mathematically correct.

| Responsibility | Details |
|---|---|
| Validate deposits | Verify USDC transferred, sharesMinted computed correctly, datum updated |
| Validate withdrawals | Verify fee calculation, netPayout correct, shares burned/minted correctly |
| Validate trades | Only vault owner can trade, USDC/ADA amounts balance correctly |
| Validate price updates | Oracle signature or operator attestation, freshness check |
| Enforce fee rate | Fee rate stored in datum, immutable or governance-controlled |
| Prevent over-withdrawal | `sharesToRedeem <= user shares`, `netPayout <= usdcBalance` |
| Datum integrity | All state variables correctly updated in output datum |

### 8.2 Backend (Off-Chain)

The backend constructs transactions and manages the user experience. It mirrors the vault calculation logic.

| Responsibility | Details |
|---|---|
| Compute share price | Query on-chain state, calculate vaultEquity and sharePrice |
| Preview operations | Show user expected sharesMinted, netPayout, feeAmount before signing |
| Build transactions | Construct Cardano transactions with correct datum updates |
| Oracle management | Fetch ADA/USDC price, sign and submit price update transactions |
| USDC liquidity | Before withdrawal, check if vault has enough USDC; if not, sell ADA first |
| Depositor dashboard | Display equity, PnL, costPerShare, share count for each user |
| Fee reporting | Track totalFeesCollected, owner fee share value |

---

## 9. Edge Cases & Constraints

### 9.1 Minimum Deposit / Withdrawal

Define a minimum deposit and withdrawal amount to prevent dust attacks and rounding issues. Recommended: 1 USDC (1,000,000 lovelace) minimum for deposits, 0.1 shares minimum for withdrawals.

### 9.2 Genesis Deposit

The first deposit must come from the vault owner. Share price is defined as 1.0 (1,000,000 in scaled integer). This establishes the initial share price baseline.

### 9.3 Zero Total Shares

If all depositors withdraw (totalShares = 0), the vault enters a dormant state. The next deposit is treated as a genesis deposit with share price reset to 1.0. Any residual USDC dust in the vault belongs to the vault owner.

### 9.4 Vault Owner Withdrawal

The vault owner can withdraw their own shares (including fee shares). The same fee logic applies — if the owner is in profit, 10% fee is charged. Fee shares minted go back to the owner themselves, so the net effect is: the owner pays a 10% fee on their non-fee profits.

### 9.5 Insufficient USDC Liquidity

If `usdcBalance < netPayout`, the withdrawal cannot proceed until the vault sells enough tokens to free up USDC. The backend must orchestrate a sell transaction before the withdrawal transaction. Alternatively, implement a withdrawal queue.

### 9.6 Rounding Dust Cleanup

After a full withdrawal, if shares or totalDeposited fall below a dust threshold (e.g., < 1 unit in scaled integer), treat them as zero and remove the depositor record from the datum.

---

## 10. Appendix: Worked Examples

### 10.1 Deposit into Operating Vault

Leader seeds 10,000 USDC (10,000 shares at $1.00). Vault buys 20,000 ADA @ $0.50. ADA rises to $0.55. Vault equity = 0 + 20,000 × 0.55 = $11,000. Share price = $1.10.

Alice deposits 5,000 USDC:

```
sharesMinted = 5,000 / 1.10 = 4,545.4545
totalShares  = 10,000 + 4,545.4545 = 14,545.4545
vaultEquity  = 11,000 + 5,000 = 16,000
Alice costPerShare = 5,000 / 4,545.4545 = $1.10
```

### 10.2 Full Withdrawal at Profit (with Fee)

Bob has 5,000 shares, totalDeposited = $5,000, costPerShare = $1.00. Current sharePrice = $1.20.

```
grossValue  = 5,000 * 1.20 = $6,000
costBasis   = $5,000
grossProfit = $6,000 - $5,000 = $1,000
feeAmount   = $1,000 * 10% = $100
feeShares   = $100 / $1.20 = 83.3333
netPayout   = $6,000 - $100 = $5,900
netPnL      = $5,900 - $5,000 = +$900
```

### 10.3 Partial Withdrawal at Loss (No Fee)

Grace has 10,000 shares, totalDeposited = $10,000, costPerShare = $1.00. SharePrice dropped to $0.90.

```
desiredAmount   = $2,000
sharesToRedeem  = 2,000 / 0.90 = 2,222.2222
fractionRedeem  = 2,222.2222 / 10,000 = 0.2222
costBasisRedeem = 10,000 * 0.2222 = $2,222.22

grossValue  = 2,222.2222 * 0.90 = $2,000
grossProfit = max(0, 2,000 - 2,222.22) = $0
feeAmount   = $0
netPayout   = $2,000

Remaining: shares = 7,777.78, totalDeposited = $7,777.78
costPerShare = $7,777.78 / 7,777.78 = $1.00  (unchanged)
```

---

*— End of Specification —*
