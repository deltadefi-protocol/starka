use aiken/collection/list
use aiken/crypto.{blake2b_224}
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction, find_input}
use cocktail.{
  input_inline_datum, key_signed, output_inline_datum, outputs_at_with_policy,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints.{policy_only_minted_token}
use deposit_utils.{process_batched_deposit_intent_validation}
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, L2DepositIntentDatum, MintIntent, VaultOracleDatum,
}
use utils.{check_mint_redeemer_is_burn_intent}

validator l2_deposit_intent(vault_oracle_nft: PolicyId) {
  spend(
    _datum: Option<L2DepositIntentDatum>,
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
    let Transaction { inputs, outputs, mint, extra_signatories, .. } = self

    when redeemer is {
      MintIntent -> {
        // Intent UTxO only contains the intent token (no deposit value)
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect L2DepositIntentDatum { amount, .. }: L2DepositIntentDatum =
          output_inline_datum(intent_output)

        // Deposit amount > 0 (tokens stored in Account UTxO, not intent)
        let is_amount_valid = !list.is_empty(amount)
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
        let (vault_balance, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            message,
            inputs,
            hydra_signers,
            hydra_node_pub_keys,
            signatures,
          )

        // 3. Process batched deposit intents with MPF
        let VaultOracleDatum { total_lp, vault_cost, lp_merkle_root, .. } =
          oracle_input_datum

        let (
          _total_intent_datum_m_value,
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

        // 4. Balance transferred via TransferIntent (verified by HydraAccount validator)
        // No deposit value check needed - tokens are in Account UTxOs

        // 5. Verify oracle output datum updated correctly
        let oracle_datum_check =
          oracle_output_datum == VaultOracleDatum {
            ..oracle_input_datum,
            total_lp: total_lp + total_lp_added,
            vault_cost: vault_cost + total_intent_datum_usd_value,
            lp_merkle_root: final_merkle_root,
          }

        // 6. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        is_prices_verified? && oracle_datum_check? && intent_burn_check?
      }
      CancelIntent -> {
        // Burn intent token, signed by depositor
        let is_burn_correct =
          policy_only_minted_token(mint, policy_id, "", -1)

        expect [intent_input] =
          vodka_inputs.inputs_at_with_policy(
            inputs,
            from_script(policy_id),
            policy_id,
          )
        expect intent_datum: L2DepositIntentDatum =
          input_inline_datum(intent_input)

        // No value refund needed (tokens are in Account UTxO, not intent)
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
