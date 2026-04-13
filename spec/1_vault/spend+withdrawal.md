# Specification - Vault

## Parameter

- `vault_oracle`: PolicyId (same policy for both Config and State oracles)

## User Action - Spend (L1 only)

1. **ProcessWithdrawal**
   - Get **State Oracle** (`VaultOracleDatum`) from **inputs** (state oracle spent in same tx)
   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to withdrawal intent mint validator

2. **DepositIntoDeltaDeFi**
   - Get **Config Oracle** (`VaultConfig`) from **reference_inputs**
   - Obtain DeltaDeFi's `AppOracleDatum` from reference_inputs
   - `app_deposit_request_token` is minted

3. **StakeRotation**
   - Get **State Oracle** (`VaultOracleDatum`) from **reference_inputs**
   - Withdrawal Script `vault_stake_rotation_script_hash` is validated

4. **VaultPluggableLogic**
   - Get **Config Oracle** (`VaultConfig`) from **reference_inputs**
   - Withdrawal Script `pluggable_logic` is validated
   - Allows L1 pluggable logic execution while State Oracle is in Hydra

## User Action - Withdrawal (L1 regular deposit and L2 only)

1. **Withdraw**
   - Get **Config Oracle** (`VaultConfig`) from **reference_inputs**
   - **Signed by `operator_account.account.master_key`**
   - Either one of below cases:
     - Create intent - deposit into other vault
     - Create intent - hydra withdrawal
