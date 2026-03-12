# Specification - L2 Deposit Intent

L2 deposit intents are created and processed inside the Hydra head.

## Parameter

- `vault_nft`: PolicyId

## Datum

- `lp_address`: Address - receiver of LP
- `amount`: `MValue` - in hydra token representation (`hydra_token_policy_id`, `hash_token(policy_id, asset_name)`)

## User Action - Spend

1. Process Intent

   - `L2DepositIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`

   - Deposit amount > 0
   - The net deposit value sent to `L2DepositIntent` address is equal to the datum value of `L2DepositIntent`

2. BurnIntent - Redeemer `BurnIntent (List<Int>, List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L2DepositIntent` is burnt with total batched amount
   - Vault UTxO input with datum (identified by `vault_nft`)
   - Vault UTxO output with updated datum:
     - `total_lp += sum(cal_lp)` across all intents
     - `vault_cost += sum(intent_usd_value)` across all intents
     - `lp_merkle_root` updated (see LP Merkle transition below)
     - All other datum fields unchanged
   - The deposit value is sent to the Vault UTxO in hydra token representation
   - Verify `prices` message using `hydra_node_pub_keys` from Vault datum:
     - `utxo_ref` in `message` is Vault UTxO
     - compute `hydra_signers = map(blake2b_224, hydra_node_pub_keys)`
     - verify ed25519 signatures against `hydra_node_pub_keys`
   - LP Merkle root transition:
     - Read Vault input datum -> `initial_root` (from `lp_merkle_root`)
     - Read Vault output datum -> `expected_final_root` (from `lp_merkle_root`)
     - For each deposit intent (chained sequentially):
       - Calculate `cal_lp = intent_usd_value * total_lp / vault_balance` (round DOWN — protects vault)
       - **New depositor** (`LPInsert`): Insert `LPRecordEntry { lp: cal_lp, cost: intent_usd_value }`. Verify `new_value` matches expected entry.
       - **Existing depositor** (`LPUpdate`): Verify `new_entry.lp == old_entry.lp + cal_lp` and `new_entry.cost == old_entry.cost + intent_usd_value`
       - Each action transitions `root_i -> root_{i+1}`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`

   - `L2DepositIntent` token is burnt
   - The intent UTxO value is returned to the depositor (refund)
   - Signed by the depositor (derived from `lp_address`)
   - No vault interaction required

## Notes

- This validator is deployed inside the Hydra head
- The Vault UTxO is the only UTxO committed to the head
- Token amounts are in hydra representation but USD conversion uses the same price oracle mechanism
- Price verification uses `hydra_node_pub_keys` from Vault datum (same as L1 — `app_oracle` is only used at CreateVault)
