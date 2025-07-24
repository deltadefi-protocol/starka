# Specification - VaultOracle

## Parameter

## Datum

- `app_oracle`: PolicyId
- `pluggable_logic`: ByteArray
- `operator_pub_key`: List<VerificationKey>
- `total_lp`: Int
- `hwm_lp_value`: Int
- `operator_charge`: Int
- `operator_key`: VerificationKeyHash
- `vault_cost`: Int
- `vault_script_hash`: ByteArray,
- `deposit_intent_script_hash`: ByteArray,
- `withdrawal_intent_script_hash`: ByteArray,
- `lp_token`: PolicyId,

## User Action

1. ProcessDeposit

   - `DepositIntent` is burnt

2. ProcessWithdrawal

   - `WithdrawalIntent` is burnt
