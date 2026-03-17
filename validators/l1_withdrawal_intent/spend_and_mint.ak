use aiken/collection/list
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  get_all_value_to_script, input_inline_datum, inputs_at_with_policy,
  inputs_with_policy, key_signed, output_inline_datum, outputs_at_with_policy,
  policy_only_minted_token,
}
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{convert_value_to_usd, verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, IntentRedeemerL1, MintIntent, VaultOracleDatum,
  WithdrawalIntentDatum,
}
use utils.{check_mint_redeemer_is_burn_intent, get_app_oracle_datum}
use withdraw_utils.{
  apply_operator_fee_share, process_batched_withdrawal_intent_validation,
}

validator l1_withdrawal_intent(vault_oracle_nft: PolicyId) {
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

  mint(redeemer: IntentRedeemerL1, policy_id: PolicyId, self: Transaction) {
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
        expect WithdrawalIntentDatum { shares_to_redeem, .. }: WithdrawalIntentDatum =
          output_inline_datum(intent_output)

        let is_amount_valid = shares_to_redeem > 0
        is_amount_valid? && is_mint_value_correct?
      }
      BurnIntent(indices, message, signatures, mpf_actions) -> {
        // 1. Get Vault Oracle input and output
        expect [vault_oracle_input] =
          inputs_with_policy(inputs, vault_oracle_nft)
        expect vault_oracle_input_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)

        expect [vault_oracle_output] =
          outputs_at_with_policy(
            outputs,
            vault_oracle_input.output.address,
            vault_oracle_nft,
          )
        expect vault_oracle_output_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        // 2. Verify prices message via app_oracle reference input
        let app_oracle_datum: AppOracleDatum =
          reference_inputs
            |> get_app_oracle_datum(vault_oracle_input_datum.app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_datum
        let HydraInfo { hydra_signers } = hydra_info
        let (vault_equity, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            vault_oracle_input_datum.hydra_node_pub_keys,
            signatures,
          )

        // 3. Process batched withdrawal intents with MPF
        let VaultOracleDatum {
          total_shares,
          total_deposited,
          operator_shares,
          operator_charge_percentage,
          operator_key,
          shares_merkle_root,
          vault_script_hash,
          total_fee_collected,
          ..
        } = vault_oracle_input_datum

        // Split mpf_actions: user actions + last action for operator fee share
        let user_action_count = list.length(indices)
        let (user_mpf_actions, operator_mpf_actions) =
          split_at(mpf_actions, user_action_count)

        let (
          total_intent_datum_shares_amount,
          total_user_receives,
          total_fee_shares,
          total_cost_removed,
          user_final_root,
        ) =
          process_batched_withdrawal_intent_validation(
            inputs,
            outputs,
            indices,
            user_mpf_actions,
            vault_equity,
            total_shares,
            operator_charge_percentage,
            prices,
            policy_id,
            shares_merkle_root,
          )

        // 4. Apply operator fee share MPF action
        let final_merkle_root =
          when operator_mpf_actions is {
            [operator_action] ->
              apply_operator_fee_share(
                user_final_root,
                total_fee_shares,
                from_verification_key(operator_key),
                operator_action,
              )
            [] ->
              if total_fee_shares <= 0 {
                user_final_root
              } else {
                fail @"Missing operator fee share MPF action"
              }
            _ -> fail @"Too many operator MPF actions"
          }

        // 5. Verify vault value unlocked equals total_user_receives
        // Get vault inputs/outputs by script hash
        expect [vault_input] =
          inputs_at_with_policy(
            inputs,
            from_script(vault_script_hash),
            vault_oracle_nft,
          )
        let value_from_vault =
          convert_value_to_usd(vault_input.output.value, prices)
        let value_to_vault =
          convert_value_to_usd(
            get_all_value_to_script(outputs, vault_script_hash),
            prices,
          )
        let vault_unlock_check =
          value_from_vault - value_to_vault == total_user_receives

        // 6. Calculate total fee collected (gross_value - user_receives)
        let total_gross_value =
          total_intent_datum_shares_amount * vault_equity / total_shares
        let total_fee = total_gross_value - total_user_receives

        // 7. Verify oracle output datum updated correctly
        let vault_oracle_datum_check =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            total_shares: total_shares - total_intent_datum_shares_amount + total_fee_shares,
            operator_shares: operator_shares + total_fee_shares,
            total_deposited: total_deposited - total_cost_removed,
            shares_merkle_root: final_merkle_root,
            total_fee_collected: total_fee_collected + total_fee,
          }

        // 8. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        // 9. Signed by operation_key from app_oracle OR operator_key from vault oracle
        let is_operation_signed =
          key_signed(extra_signatories, app_oracle_datum.operation_key)
        let is_operator_signed = key_signed(extra_signatories, operator_key)
        let is_authorized = is_operation_signed || is_operator_signed

        is_prices_verified? && vault_unlock_check? && vault_oracle_datum_check? && intent_burn_check? && is_authorized?
      }
      CancelIntent -> {
        let is_burn_correct = policy_only_minted_token(mint, policy_id, "", -1)

        expect [intent_input] =
          inputs_at_with_policy(inputs, from_script(policy_id), policy_id)
        expect intent_datum: WithdrawalIntentDatum =
          input_inline_datum(intent_input)

        expect Some(withdrawer_pkh) =
          cocktail.address_pub_key(intent_datum.withdrawer)
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
