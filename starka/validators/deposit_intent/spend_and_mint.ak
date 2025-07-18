use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, add, from_asset_list}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  key_signed, output_inline_datum, outputs_at_with_policy,
  policy_only_minted_token,
}
use types.{
  BurnIntent, DepositIntentDatum, IntentRedeemer, MintIntent, VaultOracleDatum,
}
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

  mint(redeemer: IntentRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction { inputs, outputs, mint, .. } = self

    when
      (
        redeemer,
        outputs_at_with_policy(outputs, from_script(policy_id), policy_id),
      )
    is {
      (MintIntent, [intent_output]) -> {
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect DepositIntentDatum { amount, .. }: DepositIntentDatum =
          output_inline_datum(intent_output)

        let is_value_deposited =
          intent_output.value == (
            from_asset_list(amount) |> add(policy_id, "", 1)
          )
        is_value_deposited? && is_mint_value_correct?
      }
      (BurnIntent(index_pairs, message, signatures), _) -> True
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
