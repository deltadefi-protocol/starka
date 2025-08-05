use aiken/collection/pairs
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction}
use cocktail.{key_signed}
use types.{
  ArbitrageBurnIntent, ArbitrageIntentRedeemer, PluggableLogic, VaultOracleDatum,
  VaultRedeemer, WithdrawFund,
}
use utils.{check_mint_redeemer_is_burn, get_vault_oracle_datum}

validator vault(oracle_nft: PolicyId) {
  spend(_d, redeemer: VaultRedeemer, _input: OutputReference, self: Transaction) {
    let Transaction { inputs, redeemers, .. } = self
    let vault_oracle_input_datum: VaultOracleDatum =
      inputs |> get_vault_oracle_datum(oracle_nft)
    let VaultOracleDatum { withdrawal_intent_script_hash, pluggable_logic, .. } =
      vault_oracle_input_datum
    when redeemer is {
      WithdrawFund -> {
        let mint_purpose = Mint(withdrawal_intent_script_hash)

        check_mint_redeemer_is_burn(mint_purpose, redeemers)?
      }
      PluggableLogic -> {
        let mint_purpose = Mint(pluggable_logic)
        expect Some(mint_redeemer_data) =
          redeemers |> pairs.get_first(mint_purpose)
        expect mint_redeemer: ArbitrageIntentRedeemer = mint_redeemer_data

        when mint_redeemer is {
          ArbitrageBurnIntent(_) -> True
          _ -> False
        }
      }
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
