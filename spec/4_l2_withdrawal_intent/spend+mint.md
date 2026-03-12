# Specification - L2 Withdrawal Intent

L2 withdrawal intents are created and processed inside the Hydra head.

## Parameter

- `vault_nft`: PolicyId

## Datum

- `lp_address`: Address - receiver of vault value
- `amount`: `Int` - LP tokens to withdraw

## User Action - Spend

1. Process Intent

   - `L2WithdrawalIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`

   - Amount > 0

2. BurnIntent - Redeemer `BurnIntent (List<Int>, List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L2WithdrawalIntent` is burnt with total batched amount
   - Vault UTxO input with datum (identified by `vault_nft`)
   - Vault UTxO output with updated datum:
     - `total_lp = total_lp - sum(amount) + sum(fee_lp)`
     - `operator_lp += sum(fee_lp)`
     - `vault_cost -= sum(cost_basis)`
     - `lp_merkle_root` updated (see LP Merkle transition below)
     - All other datum fields unchanged
   - Vault value decrease validated in hydra token terms — decreases by `sum(net_payout)` only, fee stays in vault
   - `net_payout = gross_value - fee` sent to user per intent in hydra token representation
   - Verify `prices` message using `hydra_node_pub_keys` from Vault datum:
     - `utxo_ref` in `message` is Vault UTxO
     - compute `hydra_signers = map(blake2b_224, hydra_node_pub_keys)`
     - verify ed25519 signatures against `hydra_node_pub_keys`
   - LP Merkle root transition:
     - Read Vault input datum -> `initial_root` (from `lp_merkle_root`)
     - Read Vault output datum -> `expected_final_root` (from `lp_merkle_root`)
     - For each withdrawal intent (chained sequentially):
       - Calculate `gross_value = amount * vault_balance / total_lp`
       - **Total withdrawal** (`LPDelete`): Deserialize `old_value` to get `lp_record.lp` and `lp_record.cost`. Verify `amount == lp_record.lp`. `cost_basis = lp_record.cost`. Delete leaf.
       - **Partial withdrawal** (`LPUpdate`): Deserialize `from` to get old entry. `cost_basis = old_entry.cost * amount / old_entry.lp`. Verify `new_entry.lp == old_entry.lp - amount` and `new_entry.cost == old_entry.cost - cost_basis`. Update leaf.
       - Fee calculation: `fee = max(0, (gross_value - cost_basis) * operator_charge_percentage / 100)` (round UP — fee never underpaid)
       - Fee shares: `fee_lp = fee * total_lp / vault_balance` (round UP — protects operator)
       - Net payout rounding: `net_payout = gross_value - fee` (round DOWN — protects vault)
       - Each withdrawer action transitions `root_i -> root_{i+1}`
     - After all withdrawer actions, apply operator fee share action:
       - Accumulate `total_fee_lp = sum(fee_lp)` across all intents
       - If `total_fee_lp > 0` and operator has existing entry: `LPUpdate` operator's entry with `new_entry.lp == old_entry.lp + total_fee_lp`, `new_entry.cost` unchanged (zero cost basis for fee shares)
       - If `total_fee_lp > 0` and operator has no existing entry: `LPInsert` with `LPRecordEntry { lp: total_fee_lp, cost: 0 }`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`

   - `L2WithdrawalIntent` token is burnt
   - The intent UTxO value is returned to the withdrawer (refund)
   - Signed by the withdrawer (derived from `lp_address`)
   - No vault interaction required

## Notes

- This validator is deployed inside the Hydra head
- The Vault UTxO is the only UTxO committed to the head
- Token amounts are in hydra representation but USD conversion uses the same price oracle mechanism
- Price verification uses `hydra_node_pub_keys` from Vault datum (same as L1 — `app_oracle` is only used at CreateVault)
