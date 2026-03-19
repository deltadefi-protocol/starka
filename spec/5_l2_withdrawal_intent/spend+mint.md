# Specification - L2 Withdrawal Intent

L2 withdrawal intents are created and processed inside the Hydra head. User redeems LP shares to receive balance in their Account UTxO.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `vault_oracle_nft`: PolicyId - must match validator parameter
- `withdrawer`: UserAccount - user account receiving funds (contains Account with account_id, master_key, operation_key)
- `shares_to_redeem`: `Int` - LP shares to withdraw

## User Action - Spend

1. Process Intent
   - `L2WithdrawalIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`
   - **Signed by withdrawer master_key** (from datum `withdrawer.master_key`)
   - `vault_oracle_nft` in datum matches validator parameter
   - Amount > 0 (`shares_to_redeem > 0`)
   - Intent UTxO only contains the intent token (no value)

2. BurnIntent - Redeemer `BurnIntent`
   - `L2WithdrawalIntent` is burnt (exactly 1)
   - Withdrawal script validated with `ProcessVaultWithdrawal` redeemer
   - Main validation logic in `hydra_account/core.ak`

3. CancelIntent - Redeemer `CancelIntent`
   - **Signed by `operation_key` from `app_oracle`**
   - No intent tokens in outputs (batch burn supported)
   - No value refund needed (intent only contains intent token)

## ProcessVaultWithdrawal (hydra_account/core.ak)

The main withdrawal logic is handled in the hydra_account withdrawal script:

**Inputs:**
- Vault Oracle (with `vault_oracle_nft`)
- L2 Withdrawal Intent (single intent, no batching)
- Vault's Account UTxO
- Withdrawer's Account UTxO

**Outputs:**
- Vault Oracle (updated)
- Vault's Account UTxO (balance decreased)
- Withdrawer's Account UTxO (balance increased)

**Validation:**
1. **Signed by `operation_key` from `app_oracle` OR `operator_account.account.master_key` from vault oracle**
2. **NO withdrawer signature required** (user already signed at MintIntent)
3. Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
4. Calculate withdrawal amounts:
   - `gross_value = shares_to_redeem * vault_equity / total_shares`
   - `cost_basis` from merkle proof
   - `fee = max(0, (gross_value - cost_basis) * operator_charge_percentage / 100)` (round UP)
   - `fee_shares = fee * total_shares / vault_equity` (round UP)
   - `net_payout = gross_value - fee`
5. Update Vault Oracle datum:
   - `total_shares = total_shares - shares_to_redeem + fee_shares`
   - `operator_shares += fee_shares`
   - `total_deposited -= cost_basis`
   - `total_fee_share_collected += fee_shares`
   - `shares_merkle_root` updated via MPF actions
6. Update Account balances:
   - Vault Account: `balance -= net_payout`
   - Withdrawer Account: `balance += net_payout`
7. Shares Merkle transition:
   - **Total withdrawal** (`SharesDelete { proof, old_value }`): `shares_to_redeem == old_entry.shares`. Delete leaf.
   - **Partial withdrawal** (`SharesUpdate { from, to_proof }`): Compute `new_entry.shares = old_entry.shares - shares_to_redeem`
   - Note: `to` value is computed, not passed in redeemer
   - Apply operator fee share action if `fee_shares > 0`

## Balance Flow

```
Vault's Account UTxO → (ProcessVaultWithdrawal) → User's Account UTxO
```

## Signing Summary

| Action | Signed By |
|--------|-----------|
| MintIntent | **User** (withdrawer.master_key) |
| BurnIntent | `operation_key` OR `operator_account.account.master_key` (via ProcessVaultWithdrawal) |
| CancelIntent | `operation_key` |

## Validation Rules (ref: vault-spec 4.6)

1. `shares_to_redeem > 0` AND `shares_to_redeem <= user_shares_balance` (from merkle proof)
2. `share_price` computed from current `vault_equity / total_shares`
3. `gross_profit = max(0, gross_value - cost_basis)` (never negative)
4. `fee = gross_profit * operator_charge_percentage / 100` (round UP)
5. `fee_shares` correctly computed and added to operator merkle record
6. `net_payout = gross_value - fee` transferred to user's Account
7. Sufficient balance in vault's Account to cover net_payout
8. `new_total_shares = old_total_shares - shares_redeemed + fee_shares`
9. `new_total_deposited = old_total_deposited - cost_basis_removed`

> **Asset Flexibility**: Script transfers ANY asset based on vault Account holdings. Backend determines payout asset composition. Scripts should never change; backend rules can evolve.

## Notes

- Deployed inside the Hydra head
- Intent UTxO only holds the intent token (tokens are stored in Account UTxOs)
- Vault Oracle is the only Starka UTxO in Hydra (funds stay in Vault on L1)
- **No TransferIntent required** - direct account balance update via ProcessVaultWithdrawal
- **No batching** - single intent per transaction
- **No double-signing** - user signs at intent creation, not at processing
- Performance fee calculated on profit (gross_value - cost_basis)
- Vault is treated as a normal user with its own Account UTxO
- User can later do regular withdrawal to get actual funds on L1
