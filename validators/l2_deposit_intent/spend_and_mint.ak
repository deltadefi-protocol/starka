use aiken/collection/list
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{OutputReference, Transaction, find_input}
use cocktail.{
  input_inline_datum, inputs_with_policy, key_signed, output_inline_datum,
  outputs_at_with_policy, outputs_with_policy, policy_only_minted_token,
  withdrawal_redeemer,
}
use hydra_dex/types.{AppOracleDatum, DexOrderBookDatum} as dd_types
use hydra_dex/utils as dd_utils
use types.{
  BurnIntentL2, CancelIntentL2, HydraAccountOperation, IntentRedeemerL2,
  L2DepositIntentDatum, MintIntentL2, ProcessVaultDeposit, VaultOracleDatum,
}
use utils.{get_app_oracle_datum}

validator l2_deposit_intent(vault_oracle_nft: PolicyId) {
  spend(
    _datum: Option<L2DepositIntentDatum>,
    _r,
    input: OutputReference,
    self: Transaction,
  ) {
    // Spend is allowed when mint redeemer is BurnIntent
    let Transaction { inputs, mint, .. } = self

    expect Some(own_input) = find_input(inputs, input)
    expect Script(own_hash) = own_input.output.address.payment_credential

    // Check that intent token is being burnt
    let is_intent_burnt =
      when
        flatten(mint)
          |> list.filter(fn(asset) { asset.1st == own_hash })
      is {
        [(_, _, minted_quantity)] -> minted_quantity < 0
        _ -> False
      }
    is_intent_burnt?
  }

  mint(redeemer: IntentRedeemerL2, policy_id: PolicyId, self: Transaction) {
    let Transaction {
      inputs,
      outputs,
      mint,
      extra_signatories,
      reference_inputs,
      redeemers,
      ..
    } = self

    when redeemer is {
      MintIntentL2 -> {
        // 1. Intent UTxO only contains the intent token (no deposit value)
        expect [intent_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        let is_mint_value_correct =
          policy_only_minted_token(mint, policy_id, "", 1)

        // 2. Parse intent datum
        expect L2DepositIntentDatum { depositor, deposit_amount }: L2DepositIntentDatum =
          output_inline_datum(intent_output)

        // 3. Deposit amount > 0 (tokens stored in Account UTxO, not intent)
        let is_amount_valid = !list.is_empty(deposit_amount)

        // 4. Signed by depositor PKH
        expect VerificationKey(depositor_pkh) = depositor.payment_credential
        let is_depositor_signed = key_signed(extra_signatories, depositor_pkh)

        is_amount_valid? && is_mint_value_correct? && is_depositor_signed?
      }

      BurnIntentL2 -> {
        // Simplified: just check burn + withdrawal script validated
        // Main logic is in hydra_account/core.ak ProcessVaultDeposit

        // 1. Check intent token is burnt (exactly 1)
        let is_intent_burnt = policy_only_minted_token(mint, policy_id, "", -1)

        // 2. Get hydra_account_script_hash from DexOrderBook
        expect [vault_oracle_input] =
          inputs_with_policy(inputs, vault_oracle_nft)
        expect vault_oracle_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)

        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, vault_oracle_datum.app_oracle)

        let DexOrderBookDatum { hydra_account_script_hash, .. }: DexOrderBookDatum =
          dd_utils.get_dex_order_book_datum(
            reference_inputs,
            app_oracle_datum.dex_order_book_token,
          )

        // 3. Check withdrawal script is validated (ProcessVaultDeposit redeemer)
        expect Some(w_redeemer) =
          withdrawal_redeemer(redeemers, hydra_account_script_hash)
        expect w_redeemer: HydraAccountOperation = w_redeemer
        let is_withdrawal_validated =
          when w_redeemer is {
            ProcessVaultDeposit { .. } -> True
            _ -> False
          }

        is_intent_burnt? && is_withdrawal_validated?
      }

      CancelIntentL2 -> {
        // Batch cancel: operation_key signed + no intent tokens in outputs

        // 1. No intent tokens in outputs (can batch burn multiple)
        let no_output_check =
          when outputs_with_policy(outputs, policy_id) is {
            [] -> True
            _ -> False
          }

        // 2. Get vault oracle to find app_oracle
        expect [vault_oracle_input] =
          inputs_with_policy(inputs, vault_oracle_nft)
        expect vault_oracle_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)

        // 3. Get app_oracle and check operation_key signature
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, vault_oracle_datum.app_oracle)
        let is_signed =
          key_signed(extra_signatories, app_oracle_datum.operation_key)

        no_output_check? && is_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
