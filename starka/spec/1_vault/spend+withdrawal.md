# Specification - Vault

## Parameter

- `oracle_nft`: The policy id of `OracleNFT`

## User Action - Spend

1. ProcessWithdrawal

   - `WithdrawalIntent` is burnt

2. PluggableLogic

   - `pluggable_logic` is mint with Redeemer `ArbitrageIntentBurn`

## User Action - Withdrawal

1. Withdraw
   - Operator's key is signed
