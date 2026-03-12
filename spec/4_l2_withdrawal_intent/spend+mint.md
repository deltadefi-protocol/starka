# Specification - L2 Withdrawal Intent

L2 withdrawal intents are created and processed inside the Hydra head. User redeems LP shares to receive balance in their Account UTxO.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `lp_address`: Address - receiver of vault value
- `amount`: `Int` - LP tokens to withdraw

## User Action - Spend

1. Process Intent

   - `L2WithdrawalIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`

   - Amount > 0
   - Intent UTxO only contains the intent token (no value)

2. BurnIntent - Redeemer `BurnIntent (List<Int>, List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L2WithdrawalIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_lp = total_lp - sum(amount) + sum(fee_lp)`
     - `operator_lp += sum(fee_lp)`
     - `vault_cost -= sum(cost_basis)`
     - `lp_merkle_root` updated
     - All other datum fields unchanged
   - Balance transferred from vault to user's Account UTxO (via TransferIntent)
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

   - `L2WithdrawalIntent` token is burnt
   - Signed by the withdrawer (derived from `lp_address`)
   - No value refund needed (intent only contains intent token)
   - No vault interaction required

## Balance Flow

```
Vault's Account UTxO → (TransferIntent) → User's Account UTxO
```

## Notes

- Deployed inside the Hydra head
- Intent UTxO only holds the intent token (tokens are stored in Account UTxOs)
- Vault Oracle is the only Starka UTxO in Hydra (LP funds stay in Vault on L1)
- Balance transfer uses HydraAccount TransferIntent mechanism
- Performance fee calculated on profit (gross_value - cost_basis)
- Vault is treated as a normal user with its own Account UTxO
- User can later do regular withdrawal to get actual funds on L1
