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
  get_all_value_to_script, input_inline_datum, inputs_at_with_policy,
  inputs_with_policy, output_inline_datum, outputs_at_with_policy, value_geq,
}
use cocktail/vodka_inputs
use cocktail/vodka_mints
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{convert_m_value_to_usd, verify_prices_oracle_messages}
use types.{
  CloseVault, CreateVault, HydraCommit, HydraDecommit, PluggableLogic,
  ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit, ProcessL2Withdrawal,
  SharesRecordEntry, UpdateConfig, VaultOracleDatum, VaultOracleMintRedeemer,
  VaultOracleSpendRedeemer,
}
use utils.{
  check_mint_redeemer_is_burn_intent, verify_pub_keys,
  withdrawal_script_validated,
}

validator vault_oracle(initial_utxo: OutputReference, app_oracle: PolicyId) {
  spend(
    datum: Option<VaultOracleDatum>,
    redeemer: VaultOracleSpendRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    expect Some(oracle_datum) = datum
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
        let mint_purpose = Mint(oracle_datum.l1_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL1Withdrawal -> {
        let mint_purpose = Mint(oracle_datum.l1_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL2Deposit -> {
        let mint_purpose = Mint(oracle_datum.l2_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL2Withdrawal -> {
        let mint_purpose = Mint(oracle_datum.l2_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      HydraCommit -> {
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        let all_hydra_signed =
          list.all(
            oracle_datum.hydra_node_pub_keys,
            fn(key) { list.has(extra_signatories, crypto.blake2b_224(key)) },
          )
        expect [oracle_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect oracle_output_datum: VaultOracleDatum =
          output_inline_datum(oracle_output)
        let is_datum_unchanged = oracle_output_datum == oracle_datum
        all_hydra_signed? && is_datum_unchanged?
      }
      HydraDecommit -> {
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        let all_hydra_signed =
          list.all(
            oracle_datum.hydra_node_pub_keys,
            fn(key) { list.has(extra_signatories, crypto.blake2b_224(key)) },
          )
        expect [oracle_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect oracle_output_datum: VaultOracleDatum =
          output_inline_datum(oracle_output)
        let is_datum_unchanged = oracle_output_datum == oracle_datum
        all_hydra_signed? && is_datum_unchanged?
      }
      PluggableLogic ->
        withdrawal_script_validated(withdrawals, oracle_datum.pluggable_logic)
      UpdateConfig -> {
        // Require all hydra_node_pub_keys signatures
        let all_hydra_signed =
          list.all(
            oracle_datum.hydra_node_pub_keys,
            fn(key) { list.has(extra_signatories, crypto.blake2b_224(key)) },
          )

        // Get oracle output
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        expect [oracle_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect oracle_output_datum: VaultOracleDatum =
          output_inline_datum(oracle_output)

        // State fields must remain unchanged
        let is_state_unchanged = and {
            oracle_output_datum.total_shares == oracle_datum.total_shares,
            oracle_output_datum.operator_shares == oracle_datum.operator_shares,
            oracle_output_datum.total_deposited == oracle_datum.total_deposited,
            oracle_output_datum.shares_merkle_root == oracle_datum.shares_merkle_root,
            oracle_output_datum.total_fee_collected == oracle_datum.total_fee_collected,
          }

        // Validate operator_charge_percentage
        let is_charge_valid =
          oracle_output_datum.operator_charge_percentage >= 0 && oracle_output_datum.operator_charge_percentage <= 100

        all_hydra_signed? && is_state_unchanged? && is_charge_valid?
      }
    }
  }

  mint(
    redeemer: VaultOracleMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let Transaction {
      inputs,
      outputs,
      mint,
      extra_signatories,
      reference_inputs,
      ..
    } = self

    when redeemer is {
      CreateVault {
        initial_deposit,
        initial_shares,
        prices_message,
        signatures,
        initial_shares_proof,
      } -> {
        // One-shot: verify initial_utxo is consumed (guarantees unique policy_id)
        let is_utxo_consumed =
          list.any(inputs, fn(input) { input.output_reference == initial_utxo })

        // Oracle NFT minted to own script address
        let to_mint = from_asset(policy_id, "", 1)
        expect [vault_oracle_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        expect vault_oracle_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        let VaultOracleDatum {
          hydra_node_pub_keys,
          operator_key,
          vault_script_hash,
          ..
        } = vault_oracle_datum
        // Get app_oracle reference input
        expect [app_oracle_ref] =
          inputs_with_policy(reference_inputs, app_oracle)
        expect InlineDatum(app_oracle_data) = app_oracle_ref.output.datum
        expect app_oracle_datum: AppOracleDatum = app_oracle_data
        let AppOracleDatum { hydra_info, operation_key, .. } = app_oracle_datum
        let HydraInfo { hydra_signers } = hydra_info

        // Verify hydra_node_pub_keys match app_oracle signers
        let are_keys_valid = verify_pub_keys(hydra_node_pub_keys, hydra_signers)

        // Verify prices message
        let (_, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            prices_message,
            inputs,
            hydra_signers,
            hydra_node_pub_keys,
            signatures,
          )

        // Compute total_deposited from initial_deposit and prices
        let computed_total_deposited =
          convert_m_value_to_usd(initial_deposit, prices)

        // Compute initial merkle root via MPF insert
        let operator_address = from_verification_key(operator_key)
        let mpf_key = cbor.serialise(operator_address)
        let initial_entry =
          SharesRecordEntry {
            shares: initial_shares,
            total_deposited: computed_total_deposited,
          }
        let mpf_value = cbor.serialise(initial_entry)
        let computed_root =
          mpf.root(
            mpf.insert(mpf.empty, mpf_key, mpf_value, initial_shares_proof),
          )

        // Validate datum fields
        let is_datum_correct = and {
            vault_oracle_datum.app_oracle == app_oracle,
            vault_oracle_datum.total_shares == initial_shares,
            vault_oracle_datum.operator_shares == initial_shares,
            vault_oracle_datum.total_deposited == computed_total_deposited,
            initial_shares == computed_total_deposited,
            vault_oracle_datum.shares_merkle_root == computed_root,
            vault_oracle_datum.operator_charge_percentage >= 0,
            vault_oracle_datum.operator_charge_percentage <= 100,
            vault_oracle_datum.is_active == True,
            vault_oracle_datum.total_fee_collected == 0,
          }

        // Initial deposit sent to vault_script_hash
        let is_deposit_in_vault =
          value_geq(
            get_all_value_to_script(outputs, vault_script_hash),
            from_asset_list(initial_deposit),
          )

        // Signed by operator_key from oracle_datum AND operation_key from app_oracle
        let is_operator_signed = list.has(extra_signatories, operator_key)
        let is_operation_signed = list.has(extra_signatories, operation_key)
        let is_mint_correct = assets.match(mint, to_mint, ==)

        and {
          is_utxo_consumed?,
          (initial_shares > 0)?,
          are_keys_valid?,
          is_prices_verified?,
          is_datum_correct?,
          is_deposit_in_vault?,
          is_operator_signed?,
          is_operation_signed?,
          is_mint_correct?,
        }
      }

      CloseVault -> {
        // Get oracle input
        expect [vault_oracle_input] =
          inputs_at_with_policy(inputs, from_script(policy_id), policy_id)
        expect vault_oracle_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)
        let VaultOracleDatum {
          operator_key,
          total_shares,
          shares_merkle_root,
          ..
        } = vault_oracle_datum
        // Get app_oracle reference input
        expect [app_oracle_ref] =
          inputs_with_policy(reference_inputs, app_oracle)
        expect InlineDatum(app_oracle_data) = app_oracle_ref.output.datum
        expect app_oracle_datum: AppOracleDatum = app_oracle_data
        let AppOracleDatum { operation_key, .. } = app_oracle_datum

        // Burn oracle NFT
        let is_burn_correct =
          vodka_mints.only_minted_token(mint, policy_id, "", -1)

        // Verify conditions
        let is_total_shares_zero = total_shares == 0
        let is_merkle_empty = mpf.is_empty(mpf.from_root(shares_merkle_root))
        // Signed by operator_key from oracle_datum AND operation_key from app_oracle
        let is_operator_signed = list.has(extra_signatories, operator_key)
        let is_operation_signed = list.has(extra_signatories, operation_key)

        is_burn_correct? && is_total_shares_zero? && is_merkle_empty? && is_operator_signed? && is_operation_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
