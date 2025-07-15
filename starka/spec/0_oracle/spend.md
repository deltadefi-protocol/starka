# Specification - AppOracle

## Parameter

## Datum

- `app_oracle`: PolicyId
- `pluggable_logic`: ByteArray
- `operator_pub_key`: List<VerificationKey>
- `total_lp`: Int
- `lp_value`: Int
- `operator_charge`: Int
- `operator_key`: VerificationKeyHash

## User Action

1. ProcessDeposit

   - `DepositIntent` is burnt

2. ProcessWithdrawal

   - `WithdrawalIntent` is burnt
