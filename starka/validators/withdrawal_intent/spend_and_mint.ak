use aiken/cbor
use aiken/collection/list
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, add, from_asset, without_lovelace}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  get_all_value_from, get_all_value_to, output_inline_datum,
  outputs_at_with_policy, outputs_with_policy, policy_only_minted_token,
  value_length,
}
use cocktail/vodka_inputs.{input_inline_datum}
use cocktail/vodka_outputs.{outputs_at}
use types.{
  AppOracleDatum, BurnIntent, HydraInfo, IntentRedeemer, Message, MintIntent,
  VaultOracleDatum, WithdrawalIntentDatum,
}
use utils.{
  cal_operator_fee, check_mint_redeemer_is_burn, get_app_oracle_datum,
  get_vault_oracle_input, verify_pub_keys, verify_signatures,
}
use withdraw_utils.{
  check_output_value_equal_to_lp_usd_value, convert_value_to_usd,
  process_batched_withdrawal_intent_validation,
}

validator withdrawal_intent(oracle_nft: PolicyId, lp_token: PolicyId) {
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
        // COMMENT: same as deposit intent
        outputs_at_with_policy(outputs, from_script(policy_id), policy_id),
      )
    is {
      (MintIntent, [intent_output]) -> {
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect WithdrawalIntentDatum { amount, .. }: WithdrawalIntentDatum =
          output_inline_datum(intent_output)

        let is_lp_locked =
          without_lovelace(intent_output.value) == (
            from_asset(lp_token, "", amount)
              |> add(policy_id, "", 1)
          )
        is_lp_locked? && is_mint_value_correct?
      }
      (BurnIntent(indices, message, signatures), _) -> {
        // - Get the vault oracle input datum
        let vault_oracle_input = get_vault_oracle_input(inputs, oracle_nft)

        expect vault_oracle_input_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)

        let VaultOracleDatum {
          app_oracle,
          node_pub_key,
          total_lp,
          hwm_lp_value,
          lp_token,
          vault_cost,
          operator_charge_percentage,
          operator_key,
          vault_script_hash,
          ..
        } = vault_oracle_input_datum

        // - Get the app oracle input datum
        let app_oracle_input_datum: AppOracleDatum =
          reference_inputs |> get_app_oracle_datum(app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_input_datum
        let HydraInfo { hydra_signers, .. } = hydra_info

        // - Verify the node public keys and signatures
        let keys_check = verify_pub_keys(node_pub_key, hydra_signers)
        let signatures_check =
          verify_signatures(node_pub_key, message, signatures)

        expect Some(signed_data) = cbor.deserialise(message)

        expect Message { vault_balance, prices, utxo_ref }: Message =
          signed_data

        let operator_fee =
          cal_operator_fee(
            vault_balance,
            hwm_lp_value,
            operator_charge_percentage,
          )
        let (total_intent_datum_lp_amount, total_intent_datum_lp_usd_value) =
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

        // - Check the vault oracle output datum is updated correctly
        expect [vault_oracle_output] = outputs_with_policy(outputs, oracle_nft)
        expect vault_oracle_output_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        let is_vault_oracle_output_value_clean =
          value_length(vault_oracle_output.value) == 2

        let vault_oracle_output_datum_check =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            total_lp: total_lp - total_intent_datum_lp_amount,
            hwm_lp_value: vault_balance - operator_fee - total_intent_datum_lp_usd_value,
            vault_cost: vault_cost - total_intent_datum_lp_usd_value,
          }

        // - Check the the LP burn amount == total_intent_datum_lp_amount
        let lp_mint_check =
          policy_only_minted_token(
            mint,
            lp_token,
            "",
            -total_intent_datum_lp_amount,
          )

        // - Check the intent burn amount == length of batched intents
        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        // - Check the operator output value == operator_fee
        // - Check the operator output address == operator_key
        let operator_output_check =
          when operator_fee > 0 is {
            True -> {
              expect [operator_output] =
                outputs_at(outputs, from_verification_key(operator_key))
              check_output_value_equal_to_lp_usd_value(
                operator_output.value,
                operator_fee,
                prices,
              )
            }
            False -> True
          }

        // - Check the vault unlock value == total_intent_datum_lp_usd_value
        // COMMENT: similarly, in prod we would have staking part for vault
        //  add 2 utils at vodka, use 
        // `get_all_value_from_script`
        // `get_all_value_to_script`
        // For completenes purpose, would also add (to be in issue)
        // `get_all_value_from_pubkey`
        // `get_all_value_to_pubkey`
        let value_from_vault =
          get_all_value_from(inputs, from_script(vault_script_hash))

        let value_to_vault =
          get_all_value_to(outputs, from_script(vault_script_hash))

        let vault_unlock_check =
          convert_value_to_usd(value_from_vault, prices) - convert_value_to_usd(
            value_to_vault,
            prices,
          ) == total_intent_datum_lp_usd_value
        // - Check the vault oracle utxo_ref is the same as the one in the signed message
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
