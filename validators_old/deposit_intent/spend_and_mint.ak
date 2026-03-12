use aiken/collection/list
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, from_asset_list}
use cardano/transaction.{
  InlineDatum, Mint, OutputReference, Transaction, find_input,
}
use cocktail.{
  get_all_value_to_script, output_inline_datum, outputs_at_with_policy,
  value_geq, value_length,
}
use cocktail/vodka_inputs.{inputs_at_with_policy}
use cocktail/vodka_mints.{policy_only_minted_token}
use deposit_utils.{process_batched_deposit_intent_validation}
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{
  BurnIntent, DepositIntentDatum, MintIntent, VaultOracleDatum, VaultStateDatum,
}
use utils.{check_mint_redeemer_is_burn, get_app_oracle_datum, get_vault_oracle_datum}

validator deposit_intent(vault_oracle_nft: PolicyId) {
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

  mint(redeemer: types.IntentRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction { inputs, outputs, mint, reference_inputs, .. } = self

    when redeemer is {
      MintIntent -> {
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect DepositIntentDatum { amount, .. }: DepositIntentDatum =
          output_inline_datum(intent_output)

        let is_value_deposited =
          value_geq(
            intent_output.value,
            from_asset_list(amount),
          )
        is_value_deposited? && is_mint_value_correct?
      }
      BurnIntent(indices, _lp_indices, message, signatures) -> {
        // 1. Get VaultOracleDatum from reference inputs
        let vault_oracle_datum: VaultOracleDatum =
          reference_inputs |> get_vault_oracle_datum(vault_oracle_nft)

        let VaultOracleDatum {
          app_oracle,
          vault_state_script_hash,
          vault_script_hash,
          lp_record_script_hash,
          hydra_node_pub_keys,
          ..
        } = vault_oracle_datum

        // 2. Get VaultStateDatum input and output
        expect [vault_state_input] =
          inputs_at_with_policy(
            inputs,
            from_script(vault_state_script_hash),
            vault_state_script_hash,
          )
        expect [vault_state_output] =
          outputs_at_with_policy(
            outputs,
            from_script(vault_state_script_hash),
            vault_state_script_hash,
          )
        expect InlineDatum(vault_state_input_datum) =
          vault_state_input.output.datum
        expect InlineDatum(vault_state_output_datum) = vault_state_output.datum
        expect vault_state_input_datum: VaultStateDatum =
          vault_state_input_datum
        expect vault_state_output_datum: VaultStateDatum =
          vault_state_output_datum

        let is_vault_state_output_clean =
          value_length(vault_state_output.value) == 2

        // 3. Verify the prices message
        let app_oracle_input_datum: AppOracleDatum =
          reference_inputs |> get_app_oracle_datum(app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_input_datum
        let HydraInfo { hydra_signers } = hydra_info
        let (vault_balance, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            hydra_node_pub_keys,
            signatures,
          )

        // 4. Process batched deposit intents with LP Record validation
        let VaultStateDatum { total_lp, vault_cost, .. } =
          vault_state_input_datum

        let (
          total_intent_datum_m_value,
          total_intent_datum_usd_value,
          total_lp_added,
          new_lp_records_minted,
        ) =
          process_batched_deposit_intent_validation(
            inputs,
            outputs,
            indices,
            vault_balance,
            total_lp,
            prices,
            policy_id,
            lp_record_script_hash,
          )

        // 5. Verify deposit value sent to vault_script_hash
        let is_deposit_sent =
          value_geq(
            get_all_value_to_script(outputs, vault_script_hash),
            from_asset_list(total_intent_datum_m_value),
          )

        // 6. Verify VaultState output datum updated correctly
        let vault_state_output_datum_check =
          vault_state_output_datum == VaultStateDatum {
            ..vault_state_input_datum,
            total_lp: total_lp + total_lp_added,
            vault_cost: vault_cost + total_intent_datum_usd_value,
          }

        // 7. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        // 8. Verify LP Record mint count (new depositors only)
        let lp_record_mint_check =
          if new_lp_records_minted > 0 {
            policy_only_minted_token(
              mint,
              lp_record_script_hash,
              "",
              new_lp_records_minted,
            )
          } else {
            True
          }

        is_prices_verified? && is_deposit_sent? && vault_state_output_datum_check? && intent_burn_check? && lp_record_mint_check? && is_vault_state_output_clean?
      }
    }
  }

  else(_) {
    fail
  }
}
