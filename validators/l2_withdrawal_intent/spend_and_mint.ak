use aiken/collection/list
use aiken/crypto.{blake2b_224}
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  input_inline_datum, key_signed, output_inline_datum, outputs_at_with_policy,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints.{policy_only_minted_token}
use hydra_dex/types.{AppOracleDatum} as dd_types
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, L2WithdrawalIntentDatum, MintIntent,
  VaultOracleDatum,
}
use utils.{check_mint_redeemer_is_burn_intent, get_app_oracle_datum}
use withdraw_utils.{
  apply_operator_fee_share, process_batched_withdrawal_intent_validation,
}

validator l2_withdrawal_intent(vault_oracle_nft: PolicyId) {
  spend(
    _datum: Option<L2WithdrawalIntentDatum>,
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
    let Transaction { inputs, outputs, mint, extra_signatories, reference_inputs, .. } =
      self

    when redeemer is {
      MintIntent -> {
        // Intent UTxO only contains the intent token (no value)
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect L2WithdrawalIntentDatum { shares_to_redeem, .. }: L2WithdrawalIntentDatum =
          output_inline_datum(intent_output)

        // Withdrawal amount > 0
        let is_amount_valid = shares_to_redeem > 0
        is_amount_valid? && is_mint_value_correct?
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

        // 2. Verify prices message using hydra_node_pub_keys (no app_oracle in Hydra)
        let hydra_node_pub_keys = oracle_input_datum.hydra_node_pub_keys
        let hydra_signers =
          list.map(hydra_node_pub_keys, fn(key) { blake2b_224(key) })
        let (vault_equity, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            hydra_node_pub_keys,
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
          total_fee_collected,
          ..
        } = oracle_input_datum

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

        // 5. Balance transferred via TransferIntent (verified by HydraAccount validator)
        // No vault value unlock check needed - tokens are in Account UTxOs

        // 6. Calculate total fee collected (gross_value - user_receives)
        let total_gross_value =
          total_intent_datum_shares_amount * vault_equity / total_shares
        let total_fee = total_gross_value - total_user_receives

        // 7. Verify oracle output datum updated correctly
        let oracle_datum_check =
          oracle_output_datum == VaultOracleDatum {
            ..oracle_input_datum,
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
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, oracle_input_datum.app_oracle)
        let is_operation_signed =
          key_signed(extra_signatories, app_oracle_datum.operation_key)
        let is_operator_signed = key_signed(extra_signatories, operator_key)
        let is_authorized = is_operation_signed || is_operator_signed

        is_prices_verified? && oracle_datum_check? && intent_burn_check? && is_authorized?
      }
      CancelIntent -> {
        // Burn intent token, signed by operation_key from app_oracle
        let is_burn_correct =
          policy_only_minted_token(mint, policy_id, "", -1)

        // Get vault oracle to find app_oracle
        expect [oracle_input] =
          vodka_inputs.inputs_with_policy(inputs, vault_oracle_nft)
        expect oracle_datum: VaultOracleDatum = input_inline_datum(oracle_input)

        // Get app_oracle and check operation_key signature
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, oracle_datum.app_oracle)
        let is_signed =
          key_signed(extra_signatories, app_oracle_datum.operation_key)

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
