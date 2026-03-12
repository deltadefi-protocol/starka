# Specification - L2 Deposit Intent

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId

## Datum

- `lp_address`: Address - receiver of LP
- `amount`: `MValue` - in hydra token representation (`hydra_token_policy_id`, `hash_token(policy_id, asset_name)`)

## User Action - Spend

1. Process Intent

   - `L2DepositIntent` is burnt

## User Action - Mint

1. Mint - Redeemer `RMint`

   - Deposit amount > 0
   - The net deposit value sent to `L2DepositIntent` address is equal to the datum value of `L2DepositIntent`

2. Burn - Redeemer `RBurn (List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L2DepositIntent` is burnt with total batched amount
   - `VaultState` input with datum
   - `VaultState` output with updated datum:
     - `total_lp += sum(cal_lp)` across all intents
     - `vault_cost += sum(intent_usd_value)` across all intents
   - The deposit value is sent to the address with `vault_script_hash` in hydra token representation
   - Verify `prices` message:
      - `utxo_ref` in `message` is `VaultState` utxo
      - verify signatures and keys
   - LP Merkle root transition:
     - Read `LP Merkle` input datum -> `initial_root`
     - Read `LP Merkle` output datum -> `expected_final_root`
     - For each deposit intent (chained sequentially):
       - Calculate `cal_lp = intent_usd_value * total_lp / vault_balance` (round DOWN — protects vault)
       - **New depositor** (`LPInsert`): Insert `LPRecordEntry { lp: cal_lp, cost: intent_usd_value }`. Verify `new_value` matches expected entry.
       - **Existing depositor** (`LPUpdate`): Verify `new_entry.lp == old_entry.lp + cal_lp` and `new_entry.cost == old_entry.cost + intent_usd_value`
       - Each action transitions `root_i -> root_{i+1}`
     - Verify `computed_final_root == expected_final_root`

## Notes

- This validator is deployed inside the Hydra head
- VaultState and LP Merkle are committed to the head alongside
- Token amounts are in hydra representation but USD conversion uses the same price oracle mechanism
