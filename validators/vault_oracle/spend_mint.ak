use aiken/cbor
use aiken/collection/list
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets.{PolicyId, from_asset_list}
use cardano/transaction.{
  InlineDatum, Mint, Output, OutputReference, Transaction, find_input,
}
use cocktail.{
  get_all_value_to_script, input_inline_datum, inputs_at_with_policy,
  inputs_with_policy, only_minted_token, output_inline_datum,
  outputs_at_with_policy, value_geq,
}
use hydra_dex/types.{AppOracleDatum, HydraInfo, UserTradeAccount} as dd_types
use price_oracle_utils.{convert_m_value_to_usd, verify_prices_oracle_messages}
use types.{
  CloseVault, HydraCommit, HydraDecommit, L1InitialDeposit, MintVault,
  PluggableLogic, ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit,
  ProcessL2Withdrawal, SharesRecordEntry, UpdateConfig, VaultOracleDatum,
  VaultOracleMintRedeemer, VaultOracleSpendRedeemer,
}
use utils.{
  check_mint_redeemer_is_burn_intent,
  validate_hydra_signatures_with_verification_key, verify_pub_keys,
  withdrawal_script_validated,
}

validator vault_oracle(initial_utxo: OutputReference, app_oracle: PolicyId) {
  spend(
    datum: Option<VaultOracleDatum>,
    redeemer: VaultOracleSpendRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    expect Some(vault_oracle_datum) = datum
    let VaultOracleDatum {
      l1_deposit_intent_script_hash,
      l1_withdrawal_intent_script_hash,
      l2_deposit_intent_script_hash,
      l2_withdrawal_intent_script_hash,
      hydra_node_pub_keys,
      pluggable_logic,
      vault_script_hash,
      total_shares,
      operator_shares,
      total_deposited,
      shares_merkle_root,
      total_fee_share_collected,
      ..
    } = vault_oracle_datum
    let Transaction {
      inputs,
      outputs,
      redeemers,
      extra_signatories,
      withdrawals,
      ..
    } = self

    when redeemer is {
      L1InitialDeposit {
        depositor,
        initial_deposit,
        prices_message,
        signatures,
        initial_shares_proof,
      } -> {
        // Precondition: vault is empty/new
        expect total_shares == 0

        // Verify prices message
        let (_, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            prices_message,
            inputs,
            hydra_node_pub_keys,
            signatures,
          )

        // Compute total_deposited from initial_deposit and prices
        let computed_total_deposited =
          convert_m_value_to_usd(initial_deposit, prices)

        // Genesis rule: initial_shares = total_deposited (share price = 1.0)
        let initial_shares = computed_total_deposited

        // Compute initial merkle root via MPF insert
        let mpf_key = cbor.serialise(depositor)
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

        // Get oracle output
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        expect [oracle_output] =
          outputs_at_with_policy(outputs, from_script(own_hash), own_hash)
        expect oracle_output_datum: VaultOracleDatum =
          output_inline_datum(oracle_output)

        // Validate output datum state fields
        let is_datum_correct = and {
            oracle_output_datum.total_shares == initial_shares,
            oracle_output_datum.operator_shares == 0,
            oracle_output_datum.total_deposited == computed_total_deposited,
            oracle_output_datum.shares_merkle_root == computed_root,
            oracle_output_datum.total_fee_share_collected == 0,
          }

        // Initial deposit sent to vault_script_hash
        let is_deposit_in_vault =
          value_geq(
            get_all_value_to_script(outputs, vault_script_hash),
            from_asset_list(initial_deposit),
          )

        // Anyone can do initial deposit (no signature required)
        and {
          (initial_shares > 0)?,
          is_prices_verified?,
          is_datum_correct?,
          is_deposit_in_vault?,
        }
      }

      // L2InitialDeposit is handled by HydraAccount validator (ProcessVaultDeposit with total_shares == 0)
      // See deltadefi-scripts/validators/hydra_account/vault_deposit.ak
      ProcessL1Deposit -> {
        let mint_purpose = Mint(l1_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL1Withdrawal -> {
        let mint_purpose = Mint(l1_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL2Deposit -> {
        let mint_purpose = Mint(l2_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      ProcessL2Withdrawal -> {
        let mint_purpose = Mint(l2_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      HydraCommit -> {
        let all_hydra_signed =
          validate_hydra_signatures_with_verification_key(
            hydra_node_pub_keys,
            extra_signatories,
          )
        all_hydra_signed?
      }
      HydraDecommit -> {
        expect Some(own_input) = find_input(inputs, input)
        let is_input_equal_output =
          list.any(outputs, fn(output: Output) { output == own_input.output })

        let all_hydra_signed =
          validate_hydra_signatures_with_verification_key(
            hydra_node_pub_keys,
            extra_signatories,
          )
        all_hydra_signed? && is_input_equal_output?
      }
      PluggableLogic ->
        withdrawal_script_validated(withdrawals, pluggable_logic)
      UpdateConfig -> {
        // Require all hydra_node_pub_keys signatures
        let all_hydra_signed =
          validate_hydra_signatures_with_verification_key(
            hydra_node_pub_keys,
            extra_signatories,
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
            oracle_output_datum.total_shares == total_shares,
            oracle_output_datum.operator_shares == operator_shares,
            oracle_output_datum.total_deposited == total_deposited,
            oracle_output_datum.shares_merkle_root == shares_merkle_root,
            oracle_output_datum.total_fee_share_collected == total_fee_share_collected,
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
      MintVault -> {
        // One-shot: verify initial_utxo is consumed (guarantees unique policy_id)
        let is_utxo_consumed =
          list.any(inputs, fn(input) { input.output_reference == initial_utxo })

        // Exactly 1 NFT minted
        let is_mint_correct = only_minted_token(mint, policy_id, "", 1)

        // Oracle NFT minted to own script address with initial datum
        expect [vault_oracle_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        expect vault_oracle_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        // Get app_oracle reference input
        expect [app_oracle_ref] =
          inputs_with_policy(reference_inputs, app_oracle)
        expect InlineDatum(app_oracle_data) = app_oracle_ref.output.datum
        expect app_oracle_datum: AppOracleDatum = app_oracle_data
        let AppOracleDatum { hydra_info, .. } = app_oracle_datum
        let HydraInfo { hydra_signers } = hydra_info

        // Verify hydra_node_pub_keys match app_oracle signers
        let are_keys_valid =
          verify_pub_keys(vault_oracle_datum.hydra_node_pub_keys, hydra_signers)

        // Validate initial datum: all state fields = 0, shares_merkle_root = null_hash
        let is_initial_state_correct = and {
            vault_oracle_datum.app_oracle == app_oracle,
            vault_oracle_datum.total_shares == 0,
            vault_oracle_datum.operator_shares == 0,
            vault_oracle_datum.total_deposited == 0,
            vault_oracle_datum.shares_merkle_root == mpf.root(mpf.empty),
            vault_oracle_datum.total_fee_share_collected == 0,
            vault_oracle_datum.operator_charge_percentage >= 0,
            vault_oracle_datum.operator_charge_percentage <= 100,
          }

        // No signatures required (anyone can create a vault)
        is_utxo_consumed? && is_mint_correct? && is_initial_state_correct? && are_keys_valid?
      }

      CloseVault -> {
        // Get oracle input
        expect [vault_oracle_input] =
          inputs_at_with_policy(inputs, from_script(policy_id), policy_id)
        expect vault_oracle_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)
        let VaultOracleDatum {
          operator_account: close_operator_account,
          total_shares,
          shares_merkle_root,
          ..
        } = vault_oracle_datum

        // Extract operator account from UserTradeAccount
        expect UserTradeAccount { account: close_operator_acc, .. } =
          close_operator_account
        expect VerificationKey(close_operator_pkh) =
          close_operator_acc.master_key

        // Get app_oracle reference input
        expect [app_oracle_ref] =
          inputs_with_policy(reference_inputs, app_oracle)
        expect InlineDatum(app_oracle_data) = app_oracle_ref.output.datum
        expect app_oracle_datum: AppOracleDatum = app_oracle_data
        let AppOracleDatum { operation_key, .. } = app_oracle_datum

        // Burn oracle NFT
        let is_burn_correct = only_minted_token(mint, policy_id, "", -1)

        // Verify conditions
        let is_total_shares_zero = total_shares == 0
        let is_merkle_empty = mpf.is_empty(mpf.from_root(shares_merkle_root))
        // Signed by operator_key from oracle_datum AND operation_key from app_oracle
        let is_operator_signed = list.has(extra_signatories, close_operator_pkh)
        let is_operation_signed = list.has(extra_signatories, operation_key)

        is_burn_correct? && is_total_shares_zero? && is_merkle_empty? && is_operator_signed? && is_operation_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
