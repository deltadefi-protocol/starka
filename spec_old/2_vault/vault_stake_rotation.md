# Specification - AccountOperation - AppVaultStakeRotation

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId

## User Action

1. Rotate App Vault Stake Key

   - Obtain `VaultOracle`, get the vault script hash
   - Obtain DeltaDeFi's `AppOracle`
   - value from vault script hash == value to vault script hash
   - Signed by DeltaDeFi operation key
