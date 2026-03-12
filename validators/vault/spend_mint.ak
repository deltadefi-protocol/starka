use aiken/cbor
use aiken/collection/list
use aiken/crypto
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, from_asset, from_asset_list}
use cardano/transaction.{
  InlineDatum, Mint, OutputReference, Transaction, find_input,
}
use cocktail.{
  input_inline_datum, inputs_with_policy, key_signed, output_inline_datum,
  outputs_at_with_policy, outputs_with_policy, value_geq,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{convert_m_value_to_usd, verify_prices_oracle_messages}
use types.{
  CloseVault, CreateVault, HydraCommit, HydraDecommit, LPRecordEntry,
  PluggableLogic, ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit,
  ProcessL2Withdrawal, Trade, VaultDatum, VaultMintRedeemer, VaultSpendRedeemer,
}
use utils.{
  check_mint_redeemer_is_burn_intent, withdrawal_script_validated,
}

validator vault(initial_utxo: OutputReference, app_oracle: PolicyId) {
  spend(
    datum: Option<VaultDatum>,
    redeemer: VaultSpendRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    expect Some(vault_datum) = datum
    let Transaction {
      inputs,
      outputs,
      redeemers,
      extra_signatories,
      withdrawals,
      ..
    } = self

    when redeemer is {
      ProcessL1Deposit -> {
        let mint_purpose =
          Mint(vault_datum.l1_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL1Withdrawal -> {
        let mint_purpose =
          Mint(vault_datum.l1_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL2Deposit -> {
        let mint_purpose =
          Mint(vault_datum.l2_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL2Withdrawal -> {
        let mint_purpose =
          Mint(vault_datum.l2_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      HydraCommit -> {
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        let all_signed =
          list.all(
            vault_datum.hydra_node_pub_keys,
            fn(key) {
              key_signed(extra_signatories, crypto.blake2b_224(key))
            },
          )
        expect [vault_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect vault_output_datum: VaultDatum =
          output_inline_datum(vault_output)
        let is_datum_unchanged = vault_output_datum == vault_datum
        all_signed? && is_datum_unchanged?
      }
      HydraDecommit -> {
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        let all_signed =
          list.all(
            vault_datum.hydra_node_pub_keys,
            fn(key) {
              key_signed(extra_signatories, crypto.blake2b_224(key))
            },
          )
        expect [vault_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect vault_output_datum: VaultDatum =
          output_inline_datum(vault_output)
        let is_datum_unchanged = vault_output_datum == vault_datum
        all_signed? && is_datum_unchanged?
      }
      Trade -> {
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        let is_signed =
          key_signed(extra_signatories, vault_datum.operator_key)
        expect [vault_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect vault_output_datum: VaultDatum =
          output_inline_datum(vault_output)
        let is_datum_unchanged = vault_output_datum == vault_datum
        is_signed? && is_datum_unchanged?
      }
      PluggableLogic ->
        withdrawal_script_validated(withdrawals, vault_datum.pluggable_logic)
    }
  }

  mint(redeemer: VaultMintRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction {
      inputs,
      outputs,
      mint,
      extra_signatories,
      ..
    } = self

    when redeemer is {
      CreateVault {
        initial_deposit,
        initial_lp,
        prices_message,
        signatures,
        initial_lp_proof,
      } -> {
        // One-shot: verify initial_utxo is consumed (guarantees unique policy_id)
        let is_utxo_consumed =
          list.any(inputs, fn(input) { input.output_reference == initial_utxo })

        // Vault NFT minted to own script address
        let to_mint = from_asset(policy_id, "", 1)
        expect [vault_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        expect vault_datum: VaultDatum = output_inline_datum(vault_output)

        // Activate app_oracle (inactive -> active)
        expect [oracle_input] = inputs_with_policy(inputs, app_oracle)
        expect [oracle_output] = outputs_with_policy(outputs, app_oracle)
        expect InlineDatum(oracle_input_data) = oracle_input.output.datum
        expect InlineDatum(oracle_output_data) = oracle_output.datum
        expect oracle_input_datum: AppOracleDatum = oracle_input_data
        expect oracle_output_datum: AppOracleDatum = oracle_output_data
        let is_oracle_updated = oracle_output_datum == oracle_input_datum

        // Verify prices message
        let AppOracleDatum { hydra_info, .. } = oracle_input_datum
        let HydraInfo { hydra_signers } = hydra_info
        let (_, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            prices_message,
            inputs,
            hydra_signers,
            vault_datum.hydra_node_pub_keys,
            signatures,
          )

        // Compute vault_cost from initial_deposit and prices
        let computed_vault_cost =
          convert_m_value_to_usd(initial_deposit, prices)

        // Compute initial merkle root via MPF insert
        let operator_address =
          from_verification_key(vault_datum.operator_key)
        let mpf_key = cbor.serialise(operator_address)
        let initial_entry =
          LPRecordEntry { lp: initial_lp, cost: computed_vault_cost }
        let mpf_value = cbor.serialise(initial_entry)
        let computed_root =
          mpf.root(
            mpf.insert(mpf.empty, mpf_key, mpf_value, initial_lp_proof),
          )

        // Validate datum fields
        let is_datum_correct = and {
            (vault_datum.total_lp == initial_lp)?,
            (vault_datum.operator_lp == initial_lp)?,
            (vault_datum.vault_cost == computed_vault_cost)?,
            (initial_lp == computed_vault_cost)?,
            (vault_datum.lp_merkle_root == computed_root)?,
            (vault_datum.app_oracle == app_oracle)?,
            (vault_datum.is_active == True)?,
          }

        // Initial deposit held in vault UTxO
        let is_deposit_in_vault =
          value_geq(vault_output.value, from_asset_list(initial_deposit))

        let is_operator_signed =
          key_signed(extra_signatories, vault_datum.operator_key)
        let is_mint_correct = assets.match(mint, to_mint, ==)

        and {
          is_utxo_consumed?,
          (initial_lp > 0)?,
          is_oracle_updated?,
          is_prices_verified?,
          is_datum_correct?,
          is_deposit_in_vault?,
          is_operator_signed?,
          is_mint_correct?,
        }
      }

      CloseVault -> {
        // Get app_oracle input/output
        expect [oracle_input] = inputs_with_policy(inputs, app_oracle)
        expect [oracle_output] = outputs_with_policy(outputs, app_oracle)
        expect InlineDatum(oracle_input_data) = oracle_input.output.datum
        expect InlineDatum(oracle_output_data) = oracle_output.datum
        expect oracle_input_datum: AppOracleDatum = oracle_input_data
        expect oracle_output_datum: AppOracleDatum = oracle_output_data
        let is_oracle_updated = oracle_output_datum == oracle_input_datum

        // Get vault input
        expect [vault_input] =
          vodka_inputs.inputs_at_with_policy(
            inputs,
            from_script(policy_id),
            policy_id,
          )
        expect vault_datum: VaultDatum = input_inline_datum(vault_input)

        // Burn vault NFT
        let is_burn_correct =
          vodka_mints.only_minted_token(mint, policy_id, "", -1)

        // Verify conditions
        let is_total_lp_zero = vault_datum.total_lp == 0
        let is_merkle_empty =
          mpf.is_empty(mpf.from_root(vault_datum.lp_merkle_root))
        let is_operator_signed =
          key_signed(extra_signatories, vault_datum.operator_key)

        is_oracle_updated? && is_burn_correct? && is_total_lp_zero? && is_merkle_empty? && is_operator_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
