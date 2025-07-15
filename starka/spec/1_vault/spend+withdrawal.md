# Specification - Vault

## Parameter

- `oracle_nft`: The policy id of `OracleNFT`

## Datum

- `app_oracle`: PolicyId
- `pluggable_logic`: ByteArray
- `operator_pub_key`: List<VerificationKey>
- `total_lp`: Int
- `lp_value`: Int
- `operator_charge`: Int
- `operator_key`: VerificationKeyHash

## User Action - Spend

1. ProcessWithdrawal

   - `WithdrawalIntent` is burnt

## User Action - Withdrawal

1. Withdraw
   - Operator's key is signed
