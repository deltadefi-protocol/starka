# Specification - L1 Withdrawal Intent

L1 withdrawal intents allow users to withdraw funds from the Trust Me Bro vault on L1. The vault performs a regular withdrawal (HydraAccount withdrawal) to get funds, then sends to user.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `lp_address`: Address - receiver of funds
- `amount`: `Int` - LP tokens to withdraw

## User Action - Spend

1. Process Intent

   - `L1WithdrawalIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`

   - Withdrawal amount > 0
   - No vault reference needed (user creates intent independently)

2. BurnIntent - Redeemer `BurnIntent (List<Int>, List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L1WithdrawalIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_lp = total_lp - sum(amount) + sum(fee_lp)`
     - `operator_lp += sum(fee_lp)`
     - `vault_cost -= sum(cost_basis)`
     - `lp_merkle_root` updated
     - All other datum fields unchanged
   - Vault performs HydraAccount withdrawal (decreases vault's account balance)
   - `net_payout = gross_value - fee` sent to user
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - LP Merkle root transition:
     - For each withdrawal intent (chained sequentially):
       - Calculate `gross_value = amount * vault_balance / total_lp`
       - **Total withdrawal** (`LPDelete`): Verify `amount == lp_record.lp`. `cost_basis = lp_record.cost`. Delete leaf.
       - **Partial withdrawal** (`LPUpdate`): `cost_basis = old_entry.cost * amount / old_entry.lp`. Verify `new_entry.lp == old_entry.lp - amount`
       - Fee calculation: `fee = max(0, (gross_value - cost_basis) * operator_charge_percentage / 100)` (round UP)
       - Fee shares: `fee_lp = fee * total_lp / vault_balance` (round UP)
       - Net payout: `net_payout = gross_value - fee` (round DOWN)
     - After all withdrawals, apply operator fee share action if `total_fee_lp > 0`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`

   - `L1WithdrawalIntent` token is burnt
   - The intent UTxO value returned to withdrawer (refund)
   - Signed by the withdrawer (derived from `lp_address`)
   - No vault interaction required

## Fund Flow

```
Vault's account balance (HydraWithdrawal) → Vault → User
```

## Notes

- Processed on L1 (after HydraDecommit)
- User redeems LP shares for actual funds
- Vault acts as a normal user doing HydraAccount withdrawal from main system
- Performance fee calculated on profit (gross_value - cost_basis)
