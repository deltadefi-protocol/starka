use cardano/address.{Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{key_signed}
use types.{DepositIntentDatum, VaultOracleDatum}
use utils.{check_mint_redeemer_is_burn, get_vault_oracle_datum}

validator deposit_intent(oracle_nft: PolicyId) {
  spend(
    _datum: Option<DepositIntentDatum>,
    _r,
    input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { inputs, redeemers, .. } = self

    expect Some(own_input) =
      inputs
        |> find_input(input)

    expect Script(own_hash) = own_input.output.address.payment_credential
    let mint_purpose = Mint(own_hash)

    check_mint_redeemer_is_burn(mint_purpose, redeemers)?
  }

  //   withdraw(_r, _a, self: Transaction) {
  //     let Transaction { inputs, extra_signatories, .. } = self

  //     let vault_oracle_input_datum: VaultOracleDatum =
  //       inputs |> get_vault_oracle_datum(oracle_nft)
  //     let VaultOracleDatum { operator_key, .. } = vault_oracle_input_datum

  //     key_signed(extra_signatories, operator_key)?
  //   }

  else(_) {
    fail
  }
}
