# Specification - Vault

## Parameter

- `oracle_nft`: The policy id of `OracleNFT`

## User Action - Spend

1. ProcessWithdrawal

   - `WithdrawalIntent` is burnt

2. PluggableLogic

   - Withdrawal Script `pluggable_logic` is validated

## User Action - Withdrawal

1. Withdraw
   - Operator's key is signed
