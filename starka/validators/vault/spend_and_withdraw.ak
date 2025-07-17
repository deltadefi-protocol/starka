use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction}
use cocktail.{key_signed}
use types.{VaultOracleDatum}
use utils.{check_mint_redeemer_is_burn, get_vault_oracle_datum}

validator vault(oracle_nft: PolicyId) {
  spend(_d, _r, _input: OutputReference, self: Transaction) {
    let Transaction { inputs, redeemers, .. } = self

    let vault_oracle_input_datum: VaultOracleDatum =
      inputs |> get_vault_oracle_datum(oracle_nft)
    let VaultOracleDatum { withdrawal_intent_script_hash, .. } =
      vault_oracle_input_datum

    let mint_purpose = Mint(withdrawal_intent_script_hash)

    check_mint_redeemer_is_burn(mint_purpose, redeemers)?
  }

  withdraw(_r, _a, self: Transaction) {
    let Transaction { inputs, extra_signatories, .. } = self

    let vault_oracle_input_datum: VaultOracleDatum =
      inputs |> get_vault_oracle_datum(oracle_nft)
    let VaultOracleDatum { operator_key, .. } = vault_oracle_input_datum

    key_signed(extra_signatories, operator_key)?
  }

  else(_) {
    fail
  }
}
