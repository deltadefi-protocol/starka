# Specification - VaultOracle

## Parameter

## Datum

- `vault_state_script_hash`: ByteArray
- `vault_script_hash`: ByteArray
- `deposit_intent_script_hash`: ByteArray
- `withdrawal_intent_script_hash`: ByteArray
- `lp_record_script_hash`: ByteArray
- `pluggable_logic`: ByteArray
- `vault_stake_rotation_script_hash`: ByteArray
- `operator_key`: VerificationKeyHash
- `operator_charge_percentage`: Int
- `operator_min_deposit_percentage`: Int
- `is_active`: False

## User Action

1. Close Vault

   - `is_active` is False
   - The current locked in current UTxO is burnt
