use aiken/collection/list
use aiken/crypto.{blake2b_224}
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, from_asset_list}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  input_inline_datum, key_signed, output_inline_datum,
  outputs_at_with_policy, value_geq,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints.{policy_only_minted_token}
use deposit_utils.{process_batched_deposit_intent_validation}
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, DepositIntentDatum, MintIntent, VaultDatum,
}
use utils.{check_mint_redeemer_is_burn_intent}

validator l2_deposit_intent(vault_nft: PolicyId) {
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
      extra_signatories,
      ..
    } = self

    when redeemer is {
      MintIntent -> {
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect DepositIntentDatum { amount, .. }: DepositIntentDatum =
          output_inline_datum(intent_output)

        let is_value_deposited =
          value_geq(intent_output.value, from_asset_list(amount))
        is_value_deposited? && is_mint_value_correct?
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

        // 2. Verify prices message using hydra_node_pub_keys (no app_oracle in Hydra)
        let hydra_node_pub_keys = vault_input_datum.hydra_node_pub_keys
        let hydra_signers =
          list.map(hydra_node_pub_keys, fn(key) { blake2b_224(key) })
        let (vault_balance, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            hydra_node_pub_keys,
            signatures,
          )

        // 3. Process batched deposit intents with MPF
        let VaultDatum { total_lp, vault_cost, lp_merkle_root, .. } =
          vault_input_datum

        let (
          total_intent_datum_m_value,
          total_intent_datum_usd_value,
          total_lp_added,
          final_merkle_root,
        ) =
          process_batched_deposit_intent_validation(
            inputs,
            indices,
            mpf_actions,
            vault_balance,
            total_lp,
            prices,
            policy_id,
            lp_merkle_root,
          )

        // 4. Verify deposit value sent to vault UTxO
        let is_deposit_sent =
          value_geq(
            vault_output.value,
            from_asset_list(total_intent_datum_m_value),
          )

        // 5. Verify vault output datum updated correctly
        let vault_datum_check =
          vault_output_datum == VaultDatum {
            ..vault_input_datum,
            total_lp: total_lp + total_lp_added,
            vault_cost: vault_cost + total_intent_datum_usd_value,
            lp_merkle_root: final_merkle_root,
          }

        // 6. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(
            mint,
            policy_id,
            "",
            -list.length(indices),
          )

        is_prices_verified? && is_deposit_sent? && vault_datum_check? && intent_burn_check?
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
        expect intent_datum: DepositIntentDatum =
          input_inline_datum(intent_input)

        expect Some(depositor_pkh) =
          cocktail.address_pub_key(intent_datum.lp_address)
        let is_signed = key_signed(extra_signatories, depositor_pkh)

        is_burn_correct? && is_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
