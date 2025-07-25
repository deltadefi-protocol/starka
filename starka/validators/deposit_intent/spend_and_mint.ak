use aiken/cbor
use aiken/collection/list
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, add, from_asset_list}
use cardano/transaction.{
  DatumHash, InlineDatum, Mint, NoDatum, OutputReference, Transaction,
  find_input,
}
use cocktail.{
  output_inline_datum, outputs_at_with_policy, outputs_with_policy,
  policy_only_minted_token, value_length,
}
use deposit_utils.{
  process_batched_deposit_intent_validation,
  process_batched_deposit_intent_validation_init,
}
use types.{
  AppOracleDatum, BurnIntent, DepositIntentDatum, HydraInfo, IntentRedeemer,
  Message, MintIntent, VaultOracleDatum,
}
use utils.{
  cal_operator_fee, check_mint_redeemer_is_burn, get_app_oracle_datum,
  get_vault_oracle_input, verify_pub_keys, verify_signatures,
}

validator deposit_intent(oracle_nft: PolicyId, lp_decimal: Int) {
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
        // - Get the vault oracle input datum
        let vault_oracle_input = get_vault_oracle_input(inputs, oracle_nft)

        let vault_oracle_input_data: Data =
          when vault_oracle_input.output.datum is {
            NoDatum -> fail @"Vault oracle input does not contain any datum"
            DatumHash(_) -> fail @"Vault oracle input datum must be inlined"
            InlineDatum(data) -> data
          }
        expect vault_oracle_input_datum: VaultOracleDatum =
          vault_oracle_input_data

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

        // - Get the app oracle input datum
        let app_oracle_input_datum: AppOracleDatum =
          reference_inputs |> get_app_oracle_datum(app_oracle)
        let AppOracleDatum {
          app_deposit_request_token,
          app_deposit_request_address,
          hydra_info,
          ..
        } = app_oracle_input_datum
        let HydraInfo { hydra_signers, .. } = hydra_info

        // - Verify the node public keys and signatures
        let keys_check = verify_pub_keys(node_pub_key, hydra_signers)
        let signatures_check =
          verify_signatures(node_pub_key, message, signatures)

        expect Some(signed_data) = cbor.deserialise(message)

        expect Message { vault_balance, prices, utxo_ref }: Message =
          signed_data

        let operator_fee =
          cal_operator_fee(vault_balance, hwm_lp_value, operator_charge)
        let (
          total_intent_datum_m_value,
          total_intent_datum_usd_value,
          total_lp_token_sent,
        ) =
          when total_lp is {
            0 ->
              process_batched_deposit_intent_validation_init(
                inputs,
                outputs,
                indices,
                prices,
                policy_id,
                lp_token,
                pluggable_logic,
                lp_decimal,
              )
            _ ->
              process_batched_deposit_intent_validation(
                inputs,
                outputs,
                indices,
                vault_balance,
                total_lp,
                operator_fee,
                prices,
                policy_id,
                lp_token,
                pluggable_logic,
              )
          }

        // - Check the app deposit request output value == batched_intent_datum_m_value
        // - Check the app deposit request output address == app_deposit_request_address
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

        // - Check the vault oracle output datum is updated correctly
        expect [vault_oracle_output] = outputs_with_policy(outputs, oracle_nft)
        expect vault_oracle_output_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        let is_vault_oracle_output_value_clean =
          value_length(vault_oracle_output.value) == 2

        let vault_oracle_output_datum_check =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            total_lp: total_lp + total_lp_token_sent,
            hwm_lp_value: vault_balance - operator_fee + total_intent_datum_usd_value,
            vault_cost: vault_cost + total_intent_datum_usd_value,
          }

        // - Check the LP token mint amount == total_lp_token_sent
        let lp_mint_check =
          policy_only_minted_token(
            mint,
            lp_token,
            pluggable_logic,
            total_lp_token_sent,
          )

        // - Check the intent burn amount == length of batched intents
        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        // - Check vault oracle utxo_ref is the same as the one in the signed message
        let utxo_ref_check = vault_oracle_input.output_reference == utxo_ref
        keys_check? && signatures_check? && utxo_ref_check? && app_deposit_request_output_check? && vault_oracle_output_datum_check? && lp_mint_check? && intent_burn_check? && is_vault_oracle_output_value_clean?
      }
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
