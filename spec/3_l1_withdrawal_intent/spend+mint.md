# Specification - L1 Withdrawal Intent

L1 withdrawal intents allow users to withdraw funds from the Trust Me Bro vault on L1. The vault performs a regular withdrawal (HydraAccount withdrawal) to get funds, then sends to user.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `withdrawer`: Address - receiver of funds
- `shares_to_redeem`: `Int` - LP shares to withdraw

## User Action - Spend

1. Process Intent
   - `L1WithdrawalIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`
   - Withdrawal amount > 0
   - No vault reference needed (user creates intent independently)

2. BurnIntent - Redeemer `BurnIntent (List<Int>, ByteArray, List<ByteArray>, List<SharesMPFAction>)`
   - **Signed by `operation_key` from `app_oracle` OR `operator_key` from vault oracle**
   - `L1WithdrawalIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_shares = total_shares - sum(shares_to_redeem) + sum(fee_shares)`
     - `operator_shares += sum(fee_shares)`
     - `total_deposited -= sum(cost_basis)`
     - `shares_merkle_root` updated
     - All other datum fields unchanged
   - Vault performs HydraAccount withdrawal (decreases vault's account balance)
   - `net_payout = gross_value - fee` sent to user
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - Shares Merkle root transition:
     - For each withdrawal intent (chained sequentially):
       - Calculate `gross_value = shares_to_redeem * vault_equity / total_shares`
       - **Total withdrawal** (`SharesDelete`): Verify `shares_to_redeem == shares_record.shares`. `cost_basis = shares_record.total_deposited`. Delete leaf.
       - **Partial withdrawal** (`SharesUpdate`): `cost_basis = old_entry.total_deposited * shares_to_redeem / old_entry.shares`. Verify `new_entry.shares == old_entry.shares - shares_to_redeem`
       - Fee calculation: `fee = max(0, (gross_value - cost_basis) * operator_charge_percentage / 100)` (round UP)
       - Fee shares: `fee_shares = fee * total_shares / vault_equity` (round UP)
       - Net payout: `net_payout = gross_value - fee` (round DOWN)
     - After all withdrawals, apply operator fee share action if `total_fee_shares > 0`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`
   - `L1WithdrawalIntent` token is burnt
   - The intent UTxO value returned to withdrawer (refund)
   - Signed by the withdrawer
   - No vault interaction required

## Fund Flow

```
Vault's account balance (HydraWithdrawal) → Vault → User
```

## Validation Rules (ref: vault-spec 4.6)

1. `shares_to_redeem > 0` AND `shares_to_redeem <= user_shares_balance` (from merkle proof)
2. `share_price` computed from current `vault_equity / total_shares`
3. `gross_profit = max(0, gross_value - cost_basis)` (never negative)
4. `fee = gross_profit * operator_charge_percentage / 100` (round UP)
5. `fee_shares` correctly computed and added to operator merkle record
6. `net_payout = gross_value - fee` actually sent to user
7. Sufficient value in vault to cover net_payout
8. `new_total_shares = old_total_shares - shares_redeemed + fee_shares`
9. `new_total_deposited = old_total_deposited - cost_basis_removed`

> **Asset Flexibility**: Script pays out ANY asset based on vault holdings. Backend determines payout asset composition. Scripts should never change; backend rules can evolve.

## Notes

- Processed on L1 (after HydraDecommit)
- User redeems shares for actual funds
- Vault acts as a normal user doing HydraAccount withdrawal from main system
- Performance fee calculated on profit (gross_value - cost_basis)
