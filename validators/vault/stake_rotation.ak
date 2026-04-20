use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use cocktail.{get_all_value_from_script, get_all_value_to_script, key_signed}
use hydra_dex/types.{AppOracleDatum} as dd_types
use types.{VaultOracleDatum}
use utils.{get_app_oracle_datum, get_vault_oracle_datum}

validator app_vault_stake_rotation(vault_oracle: PolicyId) {
  withdraw(_redeemer: Data, _credential: Credential, tx: Transaction) {
    let Transaction { inputs, outputs, reference_inputs, extra_signatories, .. } =
      tx

    let vault_oracle_datum: VaultOracleDatum =
      get_vault_oracle_datum(reference_inputs, vault_oracle)

    let VaultOracleDatum { vault_script_hash, app_oracle, .. } =
      vault_oracle_datum

    let app_oracle_datum: AppOracleDatum =
      get_app_oracle_datum(reference_inputs, app_oracle)
    //  - value from vault script hash == value to vault script hash
    let value_from_vault = get_all_value_from_script(inputs, vault_script_hash)
    let value_to_vault = get_all_value_to_script(outputs, vault_script_hash)
    let is_vault_value_unchanged =
      value_to_vault
        |> assets.match(value_from_vault, ==)
    //  - Operation key is signed
    let is_stake_rotation_authorized =
      key_signed(extra_signatories, app_oracle_datum.operation_key)

    and {
      is_vault_value_unchanged?,
      is_stake_rotation_authorized?,
    }
  }

  publish(_redeemer: Data, _credential: Certificate, tx: Transaction) {
    let Transaction { reference_inputs, extra_signatories, .. } = tx

    let vault_oracle_datum: VaultOracleDatum =
      get_vault_oracle_datum(reference_inputs, vault_oracle)

    let VaultOracleDatum { app_oracle, .. } = vault_oracle_datum
    let AppOracleDatum { operation_key, .. }: AppOracleDatum =
      get_app_oracle_datum(reference_inputs, app_oracle)

    key_signed(extra_signatories, operation_key)?
  }

  else(_) {
    fail @"unsupported purpose"
  }
}
