# Specification - VaultConfig

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId

## Datum

- `total_lp`: Int
- `operator_lp`: Int
- `operator_charge_percentage`: Int
- `operator_min_deposit_percentage`: Int
- `vault_cost`: Int
- `pluggable_logic`: ByteArray
- `vault_script_hash`: ByteArray
- `vault_stake_rotation_script_hash`: ByteArray
- `operator_key`: VerificationKeyHash

## User Action - Spend

1. ProcessDeposit

   - `DepositIntent` is burnt

2. ProcessWithdrawal

   - `WithdrawalIntent` is burnt

## User Action - Mint

1. Create Vault - `CreateVault { initial_deposit, initial_lp, prices }`

   - `VaultConfig` token is minted to own script address
   - Obtain output to `vault_config_script_hash`, obtain the datum
   - `utxo_ref` included in inputs
   - verify signatures and keys for `prices`
   - Check against the datum:
     - `total_lp`: Same as `initial_lp`
     - `operator_lp`: Same as `initial_lp`
     - `vault_cost`: Obtained by price calculation 
   - `initial_deposit` is sent to `vault_config_script_hash` script address (obtained from datum)
   - A LP record is minted to its script address, with `lp` == `initial_lp`, `cost` == `vault_cost`, and address with pub key matched `operator_key`
   - Sign by operator (obtained from datum)

2. Close Vault `CloseVault`

   - Obtain input from `vault_config_script_hash`, obtain its datum. 
   - `VaultConfig` token from the input from `vault_config_script_hash` is burnt
   - `total_lp` == 0
   - Signed by operator
