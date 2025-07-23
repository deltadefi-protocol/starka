use aiken/cbor
use aiken/collection/list
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, add, from_asset, without_lovelace}
use cardano/transaction.{
  DatumHash, InlineDatum, Mint, NoDatum, OutputReference, Transaction,
  find_input,
}
use cocktail.{
  get_all_value_from, output_inline_datum, outputs_at_with_policy,
  outputs_with_policy, policy_only_minted_token, value_length,
}
use cocktail/vodka_outputs.{outputs_at}
use types.{
  AppOracleDatum, BurnIntent, HydraInfo, IntentRedeemer, Message, MintIntent,
  VaultOracleDatum, WithdrawalIntentDatum,
}
use utils.{
  cal_operator_fee, check_mint_redeemer_is_burn, get_app_oracle_datum,
  get_vault_oracle_datum, get_vault_oracle_input, verify_pub_keys,
  verify_signatures,
}
use withdraw_utils.{
  check_output_value_equal_to_lp_usdm_value,
  process_batched_withdrawal_intent_validation,
}

validator withdrawal_intent(oracle_nft: PolicyId) {
  spend(
    _datum: Option<WithdrawalIntentDatum>,
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
        let vault_oracle_input_datum: VaultOracleDatum =
          reference_inputs |> get_vault_oracle_datum(oracle_nft)

        let VaultOracleDatum { lp_token, pluggable_logic, .. } =
          vault_oracle_input_datum
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect WithdrawalIntentDatum { amount, .. }: WithdrawalIntentDatum =
          output_inline_datum(intent_output)

        let is_lp_locked =
          without_lovelace(intent_output.value) == (
            from_asset(lp_token, pluggable_logic, amount)
              |> add(policy_id, "", 1)
          )
        is_lp_locked? && is_mint_value_correct?
      }
      (BurnIntent(indices, message, signatures), _) -> {
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
          operator_key,
          vault_script_hash,
          ..
        } = vault_oracle_input_datum

        let app_oracle_input_datum: AppOracleDatum =
          reference_inputs |> get_app_oracle_datum(app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_input_datum
        let HydraInfo { hydra_signers, .. } = hydra_info

        let keys_check = verify_pub_keys(node_pub_key, hydra_signers)
        let signatures_check =
          verify_signatures(node_pub_key, message, signatures)

        expect Some(signed_data) = cbor.deserialise(message)

        expect Message { vault_balance, prices, utxo_ref }: Message =
          signed_data

        let operator_fee =
          cal_operator_fee(vault_balance, hwm_lp_value, operator_charge)
        let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
          process_batched_withdrawal_intent_validation(
            inputs,
            outputs,
            indices,
            vault_balance,
            total_lp,
            operator_fee,
            prices,
            policy_id,
          )

        expect [vault_oracle_output] = outputs_with_policy(outputs, oracle_nft)
        expect vault_oracle_output_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        let is_vault_oracle_output_value_clean =
          value_length(vault_oracle_output.value) == 2

        let vault_oracle_output_datum_check =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            total_lp: total_lp + total_intent_datum_lp_amount,
            hwm_lp_value: vault_balance - operator_fee - total_intent_datum_lp_usdm_value,
            vault_cost: vault_cost - total_intent_datum_lp_usdm_value,
          }

        let lp_mint_check =
          policy_only_minted_token(
            mint,
            lp_token,
            pluggable_logic,
            -total_intent_datum_lp_amount,
          )

        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        expect [operator_output] =
          outputs_at(outputs, from_verification_key(operator_key))

        let operator_output_check =
          when operator_fee > 0 is {
            True ->
              check_output_value_equal_to_lp_usdm_value(
                operator_output.value,
                operator_fee,
                prices,
              )
            False -> True
          }

        let value_unlock_from_vault =
          get_all_value_from(inputs, from_script(vault_script_hash))

        let vault_unlock_check =
          check_output_value_equal_to_lp_usdm_value(
            value_unlock_from_vault,
            operator_fee + total_intent_datum_lp_usdm_value,
            prices,
          )
        let utxo_ref_check = vault_oracle_input.output_reference == utxo_ref
        keys_check? && signatures_check? && utxo_ref_check? && vault_oracle_output_datum_check? && lp_mint_check? && intent_burn_check? && is_vault_oracle_output_value_clean? && operator_output_check? && vault_unlock_check?
      }
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
