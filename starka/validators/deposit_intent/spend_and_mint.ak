use aiken/cbor
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, add, from_asset_list}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  output_inline_datum, outputs_at_with_policy, outputs_with_policy,
  policy_only_minted_token,
}
use types.{
  AppOracleDatum, BurnIntent, DepositIntentDatum, HydraInfo, IntentRedeemer,
  Message, MintIntent, VaultOracleDatum,
}
use utils.{
  cal_operator_fee, check_mint_redeemer_is_burn, get_app_oracle_datum,
  get_vault_oracle_datum, process_batched_deposit_intent_validation,
  verify_pub_keys, verify_signatures,
}

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
    let Transaction { inputs, outputs, mint, reference_inputs, .. } = self

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
      (BurnIntent(indices, message, signatures), _) -> {
        let vault_oracle_input_datum: VaultOracleDatum =
          inputs |> get_vault_oracle_datum(oracle_nft)
        let VaultOracleDatum {
          app_oracle,
          pluggable_logic,
          node_pub_key,
          total_lp,
          hwm_lp_value,
          lp_token,
          vault_cost,
          operator_charge,
          ..
        } = vault_oracle_input_datum

        let app_oracle_input_datum: AppOracleDatum =
          reference_inputs |> get_app_oracle_datum(app_oracle)
        let AppOracleDatum {
          app_deposit_request_token,
          app_deposit_request_address,
          hydra_info,
          ..
        } = app_oracle_input_datum
        let HydraInfo { hydra_signers, .. } = hydra_info

        let keys_check = verify_pub_keys(node_pub_key, hydra_signers)
        let signatures_check =
          verify_signatures(node_pub_key, message, signatures)

        expect Some(signed_data) = cbor.deserialise(message)

        expect Message { vault_balance, prices, timestamp, .. }: Message =
          signed_data
        let (
          total_intent_datum_m_value,
          total_intent_datum_usdm_value,
          total_lp_token_sent,
        ) =
          process_batched_deposit_intent_validation(
            inputs,
            outputs,
            indices,
            vault_balance,
            total_lp,
            prices,
            policy_id,
            lp_token,
            pluggable_logic,
          )

        expect [app_deposit_request_output] =
          outputs_at_with_policy(
            outputs,
            app_deposit_request_address,
            app_deposit_request_token,
          )

        let app_deposit_request_output_check =
          app_deposit_request_output.value == (
            from_asset_list(total_intent_datum_m_value)
              |> add(app_deposit_request_token, "", 1)
          )

        expect [vault_oracle_output] = outputs_with_policy(outputs, oracle_nft)
        expect vault_oracle_output_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        let operator_fee =
          cal_operator_fee(vault_balance, hwm_lp_value, operator_charge)
        let vault_oracle_output_datum_check =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            total_lp: total_lp + total_lp_token_sent,
            hwm_lp_value: vault_balance - operator_fee + total_intent_datum_usdm_value,
            vault_cost: vault_cost + total_intent_datum_usdm_value,
          }

        keys_check? && signatures_check? && app_deposit_request_output_check? && vault_oracle_output_datum_check? && policy_only_minted_token(
          mint,
          policy_id,
          pluggable_logic,
          total_lp_token_sent,
        )
      }
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
