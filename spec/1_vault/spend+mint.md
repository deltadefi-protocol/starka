# Specification - Vault

## Parameter

- `vault_oracle`: PolicyId

## User Action - Spend (L1 only)

1. ProcessWithdrawal
   - Get `VaultOracleDatum` from **inputs** (vault oracle spent in same tx)
   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to withdrawal intent mint validator

2. DepositIntoDeltaDeFi
   - Get `VaultOracleDatum` from **reference_inputs**
   - Obtain DeltaDeFi's `AppOracleDatum` from reference_inputs
   - `app_deposit_request_token` is minted

3. StakeRotation
   - Get `VaultOracleDatum` from **reference_inputs**
   - Withdrawal Script `vault_stake_rotation_script_hash` is validated

4. VaultPluggableLogic
   - Get `VaultOracleDatum` from **reference_inputs**
   - Withdrawal Script `pluggable_logic` is validated

## User Action - Withdrawal (L2 only)

1. Withdraw
   - Get `VaultOracleDatum` from **reference_inputs**
   - **Signed by `operator_key` OR `operation_key` from `app_oracle`**
   - Either one of below cases:
     - Create intent - deposit into other vault
     - Create intent - hydra withdrawal
