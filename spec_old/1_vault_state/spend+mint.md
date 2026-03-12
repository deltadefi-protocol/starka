# Specification - VaultState

## Datum

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId
- `total_lp`: Int - total LP shares outstanding
- `operator_lp`: Int - operator's LP shares (includes accumulated fee shares)
- `vault_cost`: Int - total cost basis of all depositors in USD

## User Action - Spend

1. ProcessDeposit

   - `DepositIntent` or `L2DepositIntent` is burnt
   - Datum transition:
     - `total_lp += sum(cal_lp)` across all intents in the batch
     - `vault_cost += sum(intent_usd_value)` across all intents in the batch

2. ProcessWithdrawal

   - `WithdrawalIntent` or `L2WithdrawalIntent` is burnt
   - Datum transition:
     - `total_lp = total_lp - sum(amount) + sum(fee_lp)` where `fee_lp = fee * total_lp / vault_balance`
     - `operator_lp += sum(fee_lp)` across all intents in the batch
     - `vault_cost -= sum(cost_basis)` across all intents in the batch

3. HydraCommit

   - All hydra signers sign

4. HydraDecommit

   - All hydra signers sign

## User Action - Mint

1. Create Vault - `CreateVault { initial_deposit, initial_lp, prices }`

   - Current `policy_id` token with empty string is minted to own script address, obtain the datum
   - One input from `app_oracle`, with inactive state, and one output to `app_oracle`, updating only with active state
   - Verify `prices` message:
      - `utxo_ref` included in inputs
      - verify signatures and keys for `prices`
   - Check against the datum:
     - `total_lp`: Same as `initial_lp`
     - `operator_lp`: Same as `initial_lp`
     - `vault_cost`: Obtained by price calculation
     - `initial_lp` must equal `vault_cost` (genesis share price = 1.0)
     - `vault_oracle`: Same as param `vault_oracle_nft`
   - `initial_deposit` is sent to `vault_script_hash` script address (obtained from datum)
   - A `LP Merkle` token is minted to its script address
   - LP Merkle output datum has `lp_merkle_root` computed from inserting operator's initial LP entry into empty tree
   - Redeemer includes `initial_lp_proof: Proof` (MPF insert proof for operator entry)
   - The inserted entry: key = `cbor.serialise(operator_address)`, value = `cbor.serialise(LPRecordEntry { lp: initial_lp, cost: vault_cost })`
   - Non zero initial LPs
   - Sign by operator (obtained from datum)

2. Close Vault `CloseVault`

   - Obtain only input and output with `vault_oracle` token, update `is_active` to False
   - Obtain input from `vault_state_script_hash`, obtain its datum.
   - `VaultState` token from the input from `vault_state_script_hash` is burnt
   - `LP Merkle` input datum `lp_merkle_root` must equal empty tree hash (`null_hash`)
   - `LP Merkle` token is burnt alongside `VaultState` token
   - `total_lp` == 0
   - Signed by operator
