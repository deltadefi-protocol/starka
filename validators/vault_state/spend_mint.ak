use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, from_asset, from_asset_list}
use cardano/transaction.{InlineDatum, Input, OutputReference, Transaction}
use cocktail.{
  get_all_value_to_script, input_inline_datum, inputs_at_with_policy,
  inputs_with_policy, key_signed, only_minted_token, output_inline_datum,
  outputs_at_with_policy, outputs_with_policy, value_geq,
}
use cocktail/vodka_mints.{policy_only_minted_token}
use hydra_dex/types.{AppOracleDatum, HydraInfo} as dd_types
use price_oracle_utils.{convert_m_value_to_usd, verify_prices_oracle_messages}
use types.{
  CloseVault, CreateVault, LPRecordDatum, ProcessDeposit, ProcessRedeemer,
  ProcessWithdrawal, VaultOracleDatum, VaultStateDatum, VaultStateMintRedeemer,
}
use utils.{get_app_oracle_datum, get_vault_oracle_datum}

validator vault_state(vault_oracle_nft: PolicyId) {
  spend(
    _datum: Option<VaultStateDatum>,
    redeemer: ProcessRedeemer,
    _input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { reference_inputs, mint, .. } = self
    let vault_oracle_datum: VaultOracleDatum =
      reference_inputs |> get_vault_oracle_datum(vault_oracle_nft)

    let intent_script_hash =
      when redeemer is {
        ProcessDeposit -> vault_oracle_datum.deposit_intent_script_hash
        ProcessWithdrawal -> vault_oracle_datum.withdrawal_intent_script_hash
      }

    policy_only_minted_token(mint, intent_script_hash, "", -1)
  }

  mint(redeemer: VaultStateMintRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction {
      inputs,
      outputs,
      mint,
      extra_signatories,
      reference_inputs,
      ..
    } = self

    when redeemer is {
      CreateVault { initial_deposit, initial_lp, prices_message, signatures } -> {
        // Current `policy_id` token with empty string is minted to own script address, obtain the datum
        let to_mint = from_asset(policy_id, "", 1)
        expect [vault_state_output] =
          outputs_at_with_policy(outputs, from_script(policy_id), policy_id)
        expect vault_state_datum: VaultStateDatum =
          output_inline_datum(vault_state_output)
        let VaultStateDatum { vault_oracle, total_lp, operator_lp, vault_cost } =
          vault_state_datum

        // One input from `app_oracle`, with inactive state, and one output to `app_oracle`, updating only with active state
        expect [vault_oracle_input] = inputs_with_policy(inputs, vault_oracle)
        expect [vault_oracle_output] =
          outputs_with_policy(outputs, vault_oracle)
        expect InlineDatum(oracle_input_data) = vault_oracle_input.output.datum
        expect InlineDatum(oracle_output_data) = vault_oracle_output.datum
        expect vault_oracle_input_datum: VaultOracleDatum = oracle_input_data
        expect vault_oracle_output_datum: VaultOracleDatum = oracle_output_data
        let is_vault_oracle_updated =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            is_active: True,
          }

        let VaultOracleDatum {
          app_oracle,
          vault_script_hash,
          lp_record_script_hash,
          operator_key,
          hydra_node_pub_keys,
          ..
        } = vault_oracle_input_datum

        // Verify prices message
        let app_oracle_input_datum: AppOracleDatum =
          reference_inputs |> get_app_oracle_datum(app_oracle)
        let AppOracleDatum { hydra_info, .. } = app_oracle_input_datum
        let HydraInfo { hydra_signers } = hydra_info
        let (_, prices, is_prices_verified) =
          verify_prices_oracle_messages(
            prices_message,
            inputs,
            hydra_signers,
            hydra_node_pub_keys,
            signatures,
          )

        // Check datum fields
        let is_state_datum_correct = and {
            (total_lp == initial_lp)?,
            (operator_lp == initial_lp)?,
            (vault_cost == convert_m_value_to_usd(initial_deposit, prices))?,
            (vault_oracle == vault_oracle_nft)?,
          }

        // `initial_deposit` is sent to `vault_script_hash` script address (obtained from datum)
        let is_initial_deposit_sent =
          value_geq(
            get_all_value_to_script(outputs, vault_script_hash),
            from_asset_list(initial_deposit),
          )

        // Verify LP record is minted to its script address
        let to_mint = to_mint |> assets.add(lp_record_script_hash, "", 1)
        expect [lp_record_output] =
          outputs_at_with_policy(
            outputs,
            from_script(lp_record_script_hash),
            lp_record_script_hash,
          )

        expect lp_record_datum: LPRecordDatum =
          output_inline_datum(lp_record_output)

        let is_lp_record_correct = and {
            (lp_record_datum.lp == initial_lp)?,
            (lp_record_datum.cost == vault_cost)?,
            (lp_record_datum.address == from_verification_key(operator_key))?,
          }

        // Sign by operator (obtained from datum)
        let is_operator_signed = key_signed(extra_signatories, operator_key)
        let is_mint_correct = assets.match(mint, to_mint, ==)
        and {
          (initial_lp > 0)?,
          is_vault_oracle_updated?,
          is_prices_verified?,
          is_state_datum_correct?,
          is_initial_deposit_sent?,
          is_lp_record_correct?,
          is_operator_signed?,
          is_mint_correct?,
        }
      }

      CloseVault -> {
        expect [vault_oracle_input] =
          inputs_with_policy(inputs, vault_oracle_nft)
        expect [vault_oracle_output] =
          outputs_with_policy(outputs, vault_oracle_nft)
        expect InlineDatum(oracle_input_data) = vault_oracle_input.output.datum
        expect InlineDatum(oracle_output_data) = vault_oracle_output.datum
        expect vault_oracle_input_datum: VaultOracleDatum = oracle_input_data
        expect vault_oracle_output_datum: VaultOracleDatum = oracle_output_data
        let is_vault_oracle_updated =
          vault_oracle_output_datum == VaultOracleDatum {
            ..vault_oracle_input_datum,
            is_active: False,
          }

        // Get vault_state input
        expect [vault_state_input] =
          inputs_at_with_policy(inputs, from_script(policy_id), policy_id)

        expect vault_state_datum: VaultStateDatum =
          input_inline_datum(vault_state_input)

        // Verify VaultState token is burnt
        let is_burn_correct = only_minted_token(mint, policy_id, "", -1)

        // Verify total_lp == 0
        let is_total_lp_zero = vault_state_datum.total_lp == 0

        // singed by operator
        let is_operator_signed =
          key_signed(extra_signatories, vault_oracle_input_datum.operator_key)

        is_vault_oracle_updated? && is_burn_correct? && is_total_lp_zero? && is_operator_signed?
      }
    }
  }

  else(_) {
    fail
  }
}
