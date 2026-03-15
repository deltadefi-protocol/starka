use aiken/collection/list
use aiken/crypto.{blake2b_224}
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId}
use cardano/transaction.{Input, Mint, OutputReference, Transaction, find_input}
use cocktail.{
  input_inline_datum, inputs_at_with_policy, key_signed, output_inline_datum,
  outputs_at_with_policy,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints.{policy_only_minted_token}
use deposit_utils.{process_batched_l2_deposit_intent_validation}
use hydra_dex/types.{
  AppOracleDatum, DexOrderBookDatum, HydraAccountIntent, HydraUserIntentDatum,
  MasterIntent, TransferIntent,
} as dd_types
use hydra_dex/utils.{get_dex_order_book_datum} as dd_utils
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{
  BurnIntent, CancelIntent, L2DepositIntentDatum, MValue, MintIntent,
  VaultOracleDatum,
}
use utils.{check_mint_redeemer_is_burn_intent, get_app_oracle_datum}

// Extract transfer amounts from TransferIntent inputs
fn extract_transfer_amounts(
  transfer_intent_inputs: List<Input>,
) -> List<MValue> {
  list.map(
    transfer_intent_inputs,
    fn(input) {
      expect MasterIntent { intent, .. }: HydraUserIntentDatum =
        input_inline_datum(input)
      expect TransferIntent { amount_l2, .. }: HydraAccountIntent = intent
      amount_l2
    },
  )
}

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
    let Transaction {
      inputs,
      outputs,
      mint,
      extra_signatories,
      reference_inputs,
      ..
    } = self

    when redeemer is {
      MintIntent -> {
        // Intent UTxO only contains the intent token (no deposit value)
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)
        expect L2DepositIntentDatum { deposit_amount, .. }: L2DepositIntentDatum =
          output_inline_datum(intent_output)

        // Deposit amount > 0 (tokens stored in Account UTxO, not intent)
        let is_amount_valid = !list.is_empty(deposit_amount)
        is_amount_valid? && is_mint_value_correct?
      }
      BurnIntent(indices, message, signatures, mpf_actions) -> {
        // 1. Get Vault Oracle input and output
        expect [vault_oracle_input] =
          vodka_inputs.inputs_with_policy(inputs, vault_oracle_nft)
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

        // 2. Verify prices message using hydra_node_pub_keys (no app_oracle in Hydra)
        let hydra_node_pub_keys = vault_oracle_input_datum.hydra_node_pub_keys
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

        // 3. Get app_oracle datum (needed for operation_key and dex_order_book_token)
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(
            reference_inputs,
            vault_oracle_input_datum.app_oracle,
          )

        // 4. Get DexOrderBook datum to find hydra_user_intent_script_hash
        let DexOrderBookDatum { hydra_user_intent_script_hash, .. }: DexOrderBookDatum =
          dd_utils.get_dex_order_book_datum(
            reference_inputs,
            app_oracle_datum.dex_order_book_token,
          )

        // 5. Extract transfer amounts from all TransferIntent inputs
        let transfer_intent_inputs =
          inputs_at_with_policy(
            inputs,
            from_script(hydra_user_intent_script_hash),
            hydra_user_intent_script_hash,
          )
        let transfer_amounts = extract_transfer_amounts(transfer_intent_inputs)

        // 6. Process batched L2 deposit intents with transfer amount validation
        let VaultOracleDatum {
          total_shares,
          total_deposited,
          shares_merkle_root,
          ..
        } = vault_oracle_input_datum

        let (total_intent_datum_usd_value, total_shares_added, final_merkle_root) =
          process_batched_l2_deposit_intent_validation(
            inputs,
            indices,
            mpf_actions,
            transfer_amounts,
            vault_equity,
            total_shares,
            prices,
            policy_id,
            shares_merkle_root,
          )

        // 7. Verify oracle output datum updated correctly
        let vault_oracle_datum_check =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            total_shares: total_shares + total_shares_added,
            total_deposited: total_deposited + total_intent_datum_usd_value,
            shares_merkle_root: final_merkle_root,
          }

        // 8. Verify intent burn count
        let intent_burn_check =
          policy_only_minted_token(mint, policy_id, "", -list.length(indices))

        // 9. Signed by operation_key from app_oracle
        let is_operation_signed =
          key_signed(extra_signatories, app_oracle_datum.operation_key)

        is_prices_verified? && vault_oracle_datum_check? && intent_burn_check? && is_operation_signed?
      }
      CancelIntent -> {
        // Burn intent token, signed by operation_key from app_oracle
        let is_burn_correct = policy_only_minted_token(mint, policy_id, "", -1)

        // Get vault oracle to find app_oracle
        expect [vault_oracle_input] =
          vodka_inputs.inputs_with_policy(inputs, vault_oracle_nft)
        expect vault_oracle_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)

        // Get app_oracle and check operation_key signature
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, vault_oracle_datum.app_oracle)
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
