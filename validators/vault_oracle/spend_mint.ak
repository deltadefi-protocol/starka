use aiken/collection/list
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Mint, Output, OutputReference, Transaction, find_input,
}
use cocktail.{
  input_inline_datum, inputs_at_with_policy, inputs_with_policy,
  only_minted_token, output_inline_datum, outputs_at_with_policy,
}
use hydra_dex/types.{AppOracleDatum, HydraInfo, UserTradeAccount} as dd_types
use types.{
  CloseVault, HydraCommit, HydraDecommit, MintVault, PluggableLogic,
  ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit, ProcessL2Withdrawal,
  UpdateConfig, VaultOracleDatum, VaultOracleMintRedeemer,
  VaultOracleSpendRedeemer,
}
use utils.{
  check_mint_redeemer_is_burn_intent_l1, check_mint_redeemer_is_burn_intent_l2,
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
      ProcessL1Deposit -> {
        let mint_purpose = Mint(l1_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent_l1(mint_purpose, redeemers)?
      }
      ProcessL1Withdrawal -> {
        let mint_purpose = Mint(l1_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent_l1(mint_purpose, redeemers)?
      }
      ProcessL2Deposit -> {
        let mint_purpose = Mint(l2_deposit_intent_script_hash)
        check_mint_redeemer_is_burn_intent_l2(mint_purpose, redeemers)?
      }
      ProcessL2Withdrawal -> {
        let mint_purpose = Mint(l2_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent_l2(mint_purpose, redeemers)?
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

        // Validate operator_fee_rate_bp
        let is_charge_valid =
          oracle_output_datum.operator_fee_rate_bp >= 0 && oracle_output_datum.operator_fee_rate_bp <= 100

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

    // Get app_oracle reference input
    expect [app_oracle_ref] = inputs_with_policy(reference_inputs, app_oracle)
    expect InlineDatum(app_oracle_data) = app_oracle_ref.output.datum
    expect app_oracle_datum: AppOracleDatum = app_oracle_data
    let AppOracleDatum { hydra_info, operation_key, .. } = app_oracle_datum
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
            vault_oracle_datum.operator_fee_rate_bp >= 0,
            vault_oracle_datum.operator_fee_rate_bp <= 10000,
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
