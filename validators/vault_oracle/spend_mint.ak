use aiken/collection/list
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, Transaction, find_input,
}
use cocktail.{
  group_inputs_2, group_outputs_2, input_inline_datum, inputs_with_policy,
  only_minted_token, output_inline_datum, outputs_at_with_policy,
}
use hydra_dex/types.{AppOracleDatum, HydraInfo, UserTradeAccount} as dd_types
use types.{
  BurnVault, CloseVault, HydraCommit, HydraDecommit, MintVault, PluggableLogic,
  ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit, ProcessL2Withdrawal,
  UpdateConfig, VaultConfig, VaultOracleDatum, VaultOracleMintRedeemer,
  VaultOracleSpendRedeemer,
}
use utils.{
  check_mint_redeemer_is_burn_intent_l1, check_mint_redeemer_is_burn_intent_l2,
  validate_hydra_signatures_with_verification_key, verify_pub_keys,
  withdrawal_script_validated,
}

validator vault_oracle(initial_utxo: OutputReference, app_oracle: PolicyId) {
  spend(
    datum: Option<Data>,
    redeemer: VaultOracleSpendRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    let (
      vault_config_datum,
      is_config,
      total_shares,
      operator_shares,
      total_deposited,
      shares_merkle_root,
      total_fee_share_collected,
    ) =
      when datum is {
        Some(d) ->
          if d is VaultOracleDatum {
            (
              VaultConfig {
                app_oracle: d.app_oracle,
                vault_script_hash: d.vault_script_hash,
                l1_deposit_intent_script_hash: d.l1_deposit_intent_script_hash,
                l1_withdrawal_intent_script_hash: d.l1_withdrawal_intent_script_hash,
                l2_deposit_intent_script_hash: d.l2_deposit_intent_script_hash,
                l2_withdrawal_intent_script_hash: d.l2_withdrawal_intent_script_hash,
                pluggable_logic: d.pluggable_logic,
                operator_account: d.operator_account,
                hydra_node_pub_keys: d.hydra_node_pub_keys,
              },
              False,
              d.total_shares,
              d.operator_shares,
              d.total_deposited,
              d.shares_merkle_root,
              d.total_fee_share_collected,
            )
          } else if d is VaultConfig {
            (d, True, 0, 0, 0, "", 0)
          } else {
            fail @"Invalid datum type for vault oracle input"
          }
        _ -> fail @"Vault Oracle datum must be present"
      }

    let VaultConfig {
      l1_deposit_intent_script_hash,
      l1_withdrawal_intent_script_hash,
      l2_deposit_intent_script_hash,
      l2_withdrawal_intent_script_hash,
      hydra_node_pub_keys,
      pluggable_logic,
      ..
    } = vault_config_datum
    let Transaction {
      inputs,
      outputs,
      redeemers,
      extra_signatories,
      withdrawals,
      mint,
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
        let is_state_unchanged =
          when is_config is {
            True -> and {
                oracle_output_datum.total_shares == total_shares,
                oracle_output_datum.operator_shares == operator_shares,
                oracle_output_datum.total_deposited == total_deposited,
                oracle_output_datum.shares_merkle_root == shares_merkle_root,
                oracle_output_datum.total_fee_share_collected == total_fee_share_collected,
              }
            False -> True
          }

        // Validate operator_fee_rate_bp
        let is_charge_valid =
          oracle_output_datum.operator_fee_rate_bp >= 0 && oracle_output_datum.operator_fee_rate_bp <= 100

        all_hydra_signed? && is_state_unchanged? && is_charge_valid?
      }
      BurnVault -> {
        expect Some(own_input) = find_input(inputs, input)
        expect Script(own_hash) = own_input.output.address.payment_credential
        let are_oracles_burnt =
          when
            flatten(mint)
              |> list.filter(fn(asset) { asset.1st == own_hash })
          is {
            [(_, _, minted_quantity)] -> minted_quantity == -2
            _ -> False
          }
        are_oracles_burnt?
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
        let is_mint_correct = only_minted_token(mint, policy_id, "", 2)

        // Oracle NFT minted to own script address with initial datum
        let (vault_config_outputs, vault_oracle_outputs, _) =
          group_outputs_2(
            outputs,
            fn(output: Output) {
              if output.address == from_script(policy_id) {
                let datum = output_inline_datum(output)
                if datum is VaultConfig {
                  True
                } else {
                  False
                }
              } else {
                False
              }
            },
            fn(output: Output) {
              if output.address == from_script(policy_id) {
                let datum = output_inline_datum(output)
                if datum is VaultOracleDatum {
                  True
                } else {
                  False
                }
              } else {
                False
              }
            },
          )

        expect [vault_oracle_output] = vault_oracle_outputs
        expect vault_oracle_datum: VaultOracleDatum =
          output_inline_datum(vault_oracle_output)

        expect [vault_config_output] = vault_config_outputs
        expect vault_config_datum: VaultConfig =
          output_inline_datum(vault_config_output)
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

        let is_config_matching = and {
            vault_oracle_datum.app_oracle == vault_config_datum.app_oracle,
            vault_oracle_datum.vault_script_hash == vault_config_datum.vault_script_hash,
            vault_oracle_datum.l1_deposit_intent_script_hash == vault_config_datum.l1_deposit_intent_script_hash,
            vault_oracle_datum.l1_withdrawal_intent_script_hash == vault_config_datum.l1_withdrawal_intent_script_hash,
            vault_oracle_datum.l2_deposit_intent_script_hash == vault_config_datum.l2_deposit_intent_script_hash,
            vault_oracle_datum.l2_withdrawal_intent_script_hash == vault_config_datum.l2_withdrawal_intent_script_hash,
            vault_oracle_datum.pluggable_logic == vault_config_datum.pluggable_logic,
            vault_oracle_datum.operator_account == vault_config_datum.operator_account,
            vault_oracle_datum.hydra_node_pub_keys == vault_config_datum.hydra_node_pub_keys,
          }
        // No signatures required (anyone can create a vault)
        is_utxo_consumed? && is_mint_correct? && is_initial_state_correct? && are_keys_valid? && is_config_matching?
      }

      CloseVault -> {
        // Get oracle input

        let (vault_config_inputs, vault_oracle_inputs, _) =
          group_inputs_2(
            inputs,
            fn(input: Input) {
              if input.output.address == from_script(policy_id) {
                let datum = input_inline_datum(input)
                if datum is VaultConfig {
                  True
                } else {
                  False
                }
              } else {
                False
              }
            },
            fn(input: Input) {
              if input.output.address == from_script(policy_id) {
                let datum = input_inline_datum(input)
                if datum is VaultOracleDatum {
                  True
                } else {
                  False
                }
              } else {
                False
              }
            },
          )

        expect [vault_oracle_input] = vault_oracle_inputs
        expect vault_oracle_datum: VaultOracleDatum =
          input_inline_datum(vault_oracle_input)
        let VaultOracleDatum {
          operator_account: close_operator_account,
          total_shares,
          shares_merkle_root,
          ..
        } = vault_oracle_datum

        expect [_] = vault_config_inputs

        // Extract operator account from UserTradeAccount
        expect UserTradeAccount { account: close_operator_acc, .. } =
          close_operator_account
        expect VerificationKey(close_operator_pkh) =
          close_operator_acc.master_key

        // Burn oracle NFT
        let is_burn_correct = only_minted_token(mint, policy_id, "", -2)

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
