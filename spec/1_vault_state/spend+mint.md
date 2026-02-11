# Specification - VaultState

## Datum

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId
- `total_lp`: Int
- `operator_lp`: Int
- `vault_cost`: Int

## User Action - Spend

1. ProcessDeposit

   - `DepositIntent` is burnt

2. ProcessWithdrawal

   - `WithdrawalIntent` is burnt

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
     - `vault_oracle`: Same as param `vault_oracle_nft`
   - `initial_deposit` is sent to `vault_script_hash` script address (obtained from datum)
   - A `LP record` is minted to its script address, with `lp` == `initial_lp`, `cost` == `vault_cost`, and address with pub key matched `operator_key`
   - Sign by operator (obtained from datum)

2. Close Vault `CloseVault`

   - Obtain only input and output with `vault_oracle` token, update `is_active` to False
   - Obtain input from `vault_state_script_hash`, obtain its datum. 
   - `VaultState` token from the input from `vault_state_script_hash` is burnt
   - `total_lp` == 0
   - Signed by operator
