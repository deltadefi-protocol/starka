use aiken/collection/list
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  input_inline_datum, key_signed, output_inline_datum,
  outputs_at_with_policy,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints.{policy_only_minted_token}
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{convert_value_to_usd, verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, MintIntent, VaultDatum, WithdrawalIntentDatum,
}
use utils.{check_mint_redeemer_is_burn_intent, get_app_oracle_datum}
use withdraw_utils.{
  apply_operator_fee_share, process_batched_withdrawal_intent_validation,
}

validator l1_withdrawal_intent(vault_nft: PolicyId) {
  spend(
    _datum: Option<WithdrawalIntentDatum>,
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
        expect WithdrawalIntentDatum { amount, .. }: WithdrawalIntentDatum =
          output_inline_datum(intent_output)

        let is_amount_valid = amount > 0
        is_amount_valid? && is_mint_value_correct?
      }
      BurnIntent(indices, message, signatures, mpf_actions) -> {
        // 1. Get Vault UTxO input and output
        expect [vault_input] =
          vodka_inputs.inputs_with_policy(inputs, vault_nft)
        expect vault_input_datum: VaultDatum =
          input_inline_datum(vault_input)

        expect [vault_output] =
          outputs_at_with_policy(
            outputs,
            vault_input.output.address,
            vault_nft,
          )
        expect vault_output_datum: VaultDatum =
          output_inline_datum(vault_output)

        // 2. Verify prices message via app_oracle reference input
        let app_oracle_datum: AppOracleDatum =
          reference_inputs
            |> get_app_oracle_datum(vault_input_datum.app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_datum
        let HydraInfo { hydra_signers } = hydra_info
        let (vault_balance, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            vault_input_datum.hydra_node_pub_keys,
            signatures,
          )

        // 3. Process batched withdrawal intents with MPF
        let VaultDatum {
          total_lp,
          vault_cost,
          operator_lp,
          operator_charge_percentage,
          operator_key,
          lp_merkle_root,
          ..
        } = vault_input_datum

        // Split mpf_actions: user actions + last action for operator fee share
        let user_action_count = list.length(indices)
        let (user_mpf_actions, operator_mpf_actions) =
          split_at(mpf_actions, user_action_count)

        let (
          total_intent_datum_lp_amount,
          total_user_receives,
          total_fee_lp,
          total_cost_removed,
          user_final_root,
        ) =
          process_batched_withdrawal_intent_validation(
            inputs,
            outputs,
            indices,
            user_mpf_actions,
            vault_balance,
            total_lp,
            operator_charge_percentage,
            prices,
            policy_id,
            lp_merkle_root,
          )

        // 4. Apply operator fee share MPF action
        let final_merkle_root =
          when operator_mpf_actions is {
            [operator_action] ->
              apply_operator_fee_share(
                user_final_root,
                total_fee_lp,
                from_verification_key(operator_key),
                operator_action,
              )
            [] ->
              if total_fee_lp <= 0 {
                user_final_root
              } else {
                fail @"Missing operator fee share MPF action"
              }
            _ -> fail @"Too many operator MPF actions"
          }

        // 5. Verify vault value unlocked equals total_user_receives
        let value_from_vault =
          convert_value_to_usd(vault_input.output.value, prices)
        let value_to_vault =
          convert_value_to_usd(vault_output.value, prices)
        let vault_unlock_check =
          value_from_vault - value_to_vault == total_user_receives

        // 6. Verify vault output datum updated correctly
        let vault_datum_check =
          vault_output_datum == VaultDatum {
            ..vault_input_datum,
            total_lp: total_lp - total_intent_datum_lp_amount + total_fee_lp,
            operator_lp: operator_lp + total_fee_lp,
            vault_cost: vault_cost - total_cost_removed,
            lp_merkle_root: final_merkle_root,
          }

        // 7. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(
            mint,
            policy_id,
            "",
            -list.length(indices),
          )

        is_prices_verified? && vault_unlock_check? && vault_datum_check? && intent_burn_check?
      }
      CancelIntent -> {
        let is_burn_correct =
          policy_only_minted_token(mint, policy_id, "", -1)

        expect [intent_input] =
          vodka_inputs.inputs_at_with_policy(
            inputs,
            from_script(policy_id),
            policy_id,
          )
        expect intent_datum: WithdrawalIntentDatum =
          input_inline_datum(intent_input)

        expect Some(withdrawer_pkh) =
          cocktail.address_pub_key(intent_datum.lp_address)
        let is_signed = key_signed(extra_signatories, withdrawer_pkh)

        is_burn_correct? && is_signed?
      }
    }
  }

  else(_) {
    fail
  }
}

fn split_at(xs: List<a>, n: Int) -> (List<a>, List<a>) {
  if n <= 0 {
    ([], xs)
  } else {
    when xs is {
      [] -> ([], [])
      [head, ..tail] -> {
        let (left, right) = split_at(tail, n - 1)
        ([head, ..left], right)
      }
    }
  }
}
