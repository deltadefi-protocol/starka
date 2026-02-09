use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction}
use cocktail.{key_signed}
use types.{PluggableLogic, VaultOracleDatum, VaultRedeemer, WithdrawFund}
use utils.{
  check_mint_redeemer_is_burn, get_vault_oracle_datum,
  withdrawal_script_validated,
}

validator vault(oracle_nft: PolicyId) {
  spend(_d, redeemer: VaultRedeemer, _input: OutputReference, self: Transaction) {
    let Transaction { inputs, redeemers, withdrawals, .. } = self
    let vault_oracle_input_datum: VaultOracleDatum =
      inputs |> get_vault_oracle_datum(oracle_nft)
    let VaultOracleDatum { withdrawal_intent_script_hash, pluggable_logic, .. } =
      vault_oracle_input_datum
    when redeemer is {
      WithdrawFund -> {
        let mint_purpose = Mint(withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn(mint_purpose, redeemers)?
      }
      PluggableLogic ->
        withdrawal_script_validated(withdrawals, pluggable_logic)
    }
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
