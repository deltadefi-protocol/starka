use aiken/collection/list
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, from_asset_list}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  get_all_value_to_script, input_inline_datum, key_signed, output_inline_datum,
  outputs_at_with_policy, value_geq,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints.{policy_only_minted_token}
use deposit_utils.{process_batched_deposit_intent_validation}
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, DepositIntentDatum, MintIntent, VaultOracleDatum,
}
use utils.{check_mint_redeemer_is_burn_intent, get_app_oracle_datum}

validator l1_deposit_intent(vault_oracle_nft: PolicyId) {
  spend(
    _datum: Option<DepositIntentDatum>,
    _r,
    input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { inputs, redeemers, .. } = self

    expect Some(own_input) = find_input(inputs, input)
    expect Script(own_hash) = own_input.output.address.payment_credential
    let mint_purpose = Mint(own_hash)

    check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
  }

  mint(redeemer: types.IntentRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction {
      inputs,
      outputs,
      mint,
      reference_inputs,
      extra_signatories,
      ..
    } = self

    when redeemer is {
      MintIntent -> {
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect DepositIntentDatum { deposit_amount, .. }: DepositIntentDatum =
          output_inline_datum(intent_output)

        let is_value_deposited =
          value_geq(intent_output.value, from_asset_list(deposit_amount))
        is_value_deposited? && is_mint_value_correct?
      }
      BurnIntent(indices, message, signatures, mpf_actions) -> {
        // 1. Get Vault Oracle input and output
        expect [oracle_input] =
          vodka_inputs.inputs_with_policy(inputs, vault_oracle_nft)
        expect oracle_input_datum: VaultOracleDatum =
          input_inline_datum(oracle_input)

        expect [oracle_output] =
          outputs_at_with_policy(
            outputs,
            oracle_input.output.address,
            vault_oracle_nft,
          )
        expect oracle_output_datum: VaultOracleDatum =
          output_inline_datum(oracle_output)

        // 2. Verify prices message via app_oracle reference input
        let app_oracle_datum: AppOracleDatum =
          reference_inputs
            |> get_app_oracle_datum(oracle_input_datum.app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_datum
        let HydraInfo { hydra_signers } = hydra_info
        let (vault_equity, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            oracle_input_datum.hydra_node_pub_keys,
            signatures,
          )

        // 3. Process batched deposit intents with MPF
        let VaultOracleDatum {
          total_shares,
          total_deposited,
          shares_merkle_root,
          ..
        } = oracle_input_datum

        let (
          total_intent_datum_m_value,
          total_intent_datum_usd_value,
          total_shares_added,
          final_merkle_root,
        ) =
          process_batched_deposit_intent_validation(
            inputs,
            indices,
            mpf_actions,
            vault_equity,
            total_shares,
            prices,
            policy_id,
            shares_merkle_root,
          )

        // 4. Verify deposit value sent to vault script
        let is_deposit_sent =
          value_geq(
            get_all_value_to_script(outputs, oracle_input_datum.vault_script_hash),
            from_asset_list(total_intent_datum_m_value),
          )

        // 5. Verify oracle output datum updated correctly
        let oracle_datum_check =
          oracle_output_datum == VaultOracleDatum {
            ..oracle_input_datum,
            total_shares: total_shares + total_shares_added,
            total_deposited: total_deposited + total_intent_datum_usd_value,
            shares_merkle_root: final_merkle_root,
          }

        // 6. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(
            mint,
            policy_id,
            "",
            -list.length(indices),
          )

        // 7. Signed by operation_key from app_oracle
        let is_operation_signed =
          key_signed(extra_signatories, app_oracle_datum.operation_key)

        is_prices_verified? && is_deposit_sent? && oracle_datum_check? && intent_burn_check? && is_operation_signed?
      }
      CancelIntent -> {
        // Burn intent token, signed by depositor
        let is_burn_correct =
          policy_only_minted_token(mint, policy_id, "", -1)

        // Find the intent input to get depositor address
        expect [intent_input] =
          vodka_inputs.inputs_at_with_policy(
            inputs,
            from_script(policy_id),
            policy_id,
          )
        expect intent_datum: DepositIntentDatum =
          input_inline_datum(intent_input)

        expect Some(depositor_pkh) =
          cocktail.address_pub_key(intent_datum.depositor)
        let is_signed = key_signed(extra_signatories, depositor_pkh)

        is_burn_correct? && is_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
