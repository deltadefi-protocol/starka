use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx,
  required_signer_hash, script_withdrawal, tx_in, tx_in_inline_datum, tx_out,
  tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_hydra_signer_1, mock_hydra_signer_2, mock_hydra_signer_3,
  mock_initial_utxo, mock_l1_deposit_intent_script_hash,
  mock_l1_withdrawal_intent_script_hash, mock_l2_deposit_intent_script_hash,
  mock_l2_withdrawal_intent_script_hash, mock_pluggable_logic, mock_vault_nft,
  mock_vault_oracle_datum,
}
use types.{
  BurnIntent, CancelIntent, HydraCommit, HydraDecommit, PluggableLogic,
  ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit, ProcessL2Withdrawal,
  UpdateConfig, VaultOracleDatum, VaultOracleSpendRedeemer,
}
use vault_oracle/spend_mint as vault_oracle

// ========== ProcessIntent Test Case ==========

type ProcessIntentTestCase {
  is_intent_burnt: Bool,
  is_burn_intent_redeemer: Bool,
}

fn default_process_intent_test_case() -> ProcessIntentTestCase {
  ProcessIntentTestCase { is_intent_burnt: True, is_burn_intent_redeemer: True }
}

fn mock_process_intent_tx(
  intent_script_hash: ByteArray,
  test_case: ProcessIntentTestCase,
) -> Transaction {
  let ProcessIntentTestCase { is_intent_burnt, is_burn_intent_redeemer } =
    test_case

  let burn_redeemer: Data =
    if is_burn_intent_redeemer {
      BurnIntent([], "", [], [])
    } else {
      // Use some other redeemer that's not BurnIntent
      CancelIntent
    }

  mocktail_tx()
    |> mint(is_intent_burnt, -1, intent_script_hash, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(intent_script_hash), burn_redeemer))
}

fn run_process_intent(
  intent_script_hash: ByteArray,
  redeemer: VaultOracleSpendRedeemer,
  test_case: ProcessIntentTestCase,
) -> Bool {
  let tx = mock_process_intent_tx(intent_script_hash, test_case)
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_oracle_datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== ProcessL1Deposit Tests ==========

test s0_spend_success_process_l1_deposit() {
  run_process_intent(
    mock_l1_deposit_intent_script_hash,
    ProcessL1Deposit,
    default_process_intent_test_case(),
  )
}

test s0_spend_fail_process_l1_deposit_without_burn_intent_redeemer() {
  let test_case =
    ProcessIntentTestCase {
      ..default_process_intent_test_case(),
      is_burn_intent_redeemer: False,
    }
  !run_process_intent(
    mock_l1_deposit_intent_script_hash,
    ProcessL1Deposit,
    test_case,
  )
}

// ========== ProcessL1Withdrawal Tests ==========

test s0_spend_success_process_l1_withdrawal() {
  run_process_intent(
    mock_l1_withdrawal_intent_script_hash,
    ProcessL1Withdrawal,
    default_process_intent_test_case(),
  )
}

// ========== ProcessL2Deposit Tests ==========

test s0_spend_success_process_l2_deposit() {
  run_process_intent(
    mock_l2_deposit_intent_script_hash,
    ProcessL2Deposit,
    default_process_intent_test_case(),
  )
}

// ========== ProcessL2Withdrawal Tests ==========

test s0_spend_success_process_l2_withdrawal() {
  run_process_intent(
    mock_l2_withdrawal_intent_script_hash,
    ProcessL2Withdrawal,
    default_process_intent_test_case(),
  )
}

// ========== HydraCommit Test Case ==========

type HydraCommitTestCase {
  is_hydra_signer_1_signed: Bool,
  is_hydra_signer_2_signed: Bool,
  is_hydra_signer_3_signed: Bool,
}

fn default_hydra_commit_test_case() -> HydraCommitTestCase {
  HydraCommitTestCase {
    is_hydra_signer_1_signed: True,
    is_hydra_signer_2_signed: True,
    is_hydra_signer_3_signed: True,
  }
}

fn mock_hydra_commit_tx(test_case: HydraCommitTestCase) -> Transaction {
  let HydraCommitTestCase {
    is_hydra_signer_1_signed,
    is_hydra_signer_2_signed,
    is_hydra_signer_3_signed,
  } = test_case

  mocktail_tx()
    |> required_signer_hash(is_hydra_signer_1_signed, mock_hydra_signer_1)
    |> required_signer_hash(is_hydra_signer_2_signed, mock_hydra_signer_2)
    |> required_signer_hash(is_hydra_signer_3_signed, mock_hydra_signer_3)
    |> complete()
}

fn run_hydra_commit(test_case: HydraCommitTestCase) -> Bool {
  let tx = mock_hydra_commit_tx(test_case)
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_oracle_datum),
    HydraCommit,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== HydraCommit Tests ==========

test s0_spend_success_hydra_commit() {
  run_hydra_commit(default_hydra_commit_test_case())
}

test s0_spend_fail_hydra_commit_without_signer_1() {
  let test_case =
    HydraCommitTestCase {
      ..default_hydra_commit_test_case(),
      is_hydra_signer_1_signed: False,
    }
  !run_hydra_commit(test_case)
}

test s0_spend_fail_hydra_commit_without_signer_2() {
  let test_case =
    HydraCommitTestCase {
      ..default_hydra_commit_test_case(),
      is_hydra_signer_2_signed: False,
    }
  !run_hydra_commit(test_case)
}

test s0_spend_fail_hydra_commit_without_signer_3() {
  let test_case =
    HydraCommitTestCase {
      ..default_hydra_commit_test_case(),
      is_hydra_signer_3_signed: False,
    }
  !run_hydra_commit(test_case)
}

// ========== HydraDecommit Test Case ==========

type HydraDecommitTestCase {
  is_hydra_signer_1_signed: Bool,
  is_hydra_signer_2_signed: Bool,
  is_hydra_signer_3_signed: Bool,
  is_input_equal_output: Bool,
}

fn default_hydra_decommit_test_case() -> HydraDecommitTestCase {
  HydraDecommitTestCase {
    is_hydra_signer_1_signed: True,
    is_hydra_signer_2_signed: True,
    is_hydra_signer_3_signed: True,
    is_input_equal_output: True,
  }
}

fn mock_hydra_decommit_tx(test_case: HydraDecommitTestCase) -> Transaction {
  let HydraDecommitTestCase {
    is_hydra_signer_1_signed,
    is_hydra_signer_2_signed,
    is_hydra_signer_3_signed,
    is_input_equal_output,
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_value = from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  let output_value =
    if is_input_equal_output {
      vault_value
    } else {
      from_asset(mock_vault_nft, "", 1) |> add("", "", 3_000_000)
    }

  let output_datum =
    if is_input_equal_output {
      mock_vault_oracle_datum
    } else {
      VaultOracleDatum { ..mock_vault_oracle_datum, total_shares: 999 }
    }

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, vault_value, vault_oracle_address)
    |> tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> tx_out(True, vault_oracle_address, output_value)
    |> tx_out_inline_datum(True, output_datum)
    |> required_signer_hash(is_hydra_signer_1_signed, mock_hydra_signer_1)
    |> required_signer_hash(is_hydra_signer_2_signed, mock_hydra_signer_2)
    |> required_signer_hash(is_hydra_signer_3_signed, mock_hydra_signer_3)
    |> complete()
}

fn run_hydra_decommit(test_case: HydraDecommitTestCase) -> Bool {
  let tx = mock_hydra_decommit_tx(test_case)
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_oracle_datum),
    HydraDecommit,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== HydraDecommit Tests ==========

test s0_spend_success_hydra_decommit() {
  run_hydra_decommit(default_hydra_decommit_test_case())
}

test s0_spend_fail_hydra_decommit_without_signer_1() {
  let test_case =
    HydraDecommitTestCase {
      ..default_hydra_decommit_test_case(),
      is_hydra_signer_1_signed: False,
    }
  !run_hydra_decommit(test_case)
}

test s0_spend_fail_hydra_decommit_without_signer_2() {
  let test_case =
    HydraDecommitTestCase {
      ..default_hydra_decommit_test_case(),
      is_hydra_signer_2_signed: False,
    }
  !run_hydra_decommit(test_case)
}

test s0_spend_fail_hydra_decommit_without_signer_3() {
  let test_case =
    HydraDecommitTestCase {
      ..default_hydra_decommit_test_case(),
      is_hydra_signer_3_signed: False,
    }
  !run_hydra_decommit(test_case)
}

test s0_spend_fail_hydra_decommit_when_input_not_equal_output() {
  let test_case =
    HydraDecommitTestCase {
      ..default_hydra_decommit_test_case(),
      is_input_equal_output: False,
    }
  !run_hydra_decommit(test_case)
}

// ========== PluggableLogic Test Case ==========

type PluggableLogicTestCase {
  is_withdrawal_script_validated: Bool,
}

fn default_pluggable_logic_test_case() -> PluggableLogicTestCase {
  PluggableLogicTestCase { is_withdrawal_script_validated: True }
}

fn mock_pluggable_logic_tx(test_case: PluggableLogicTestCase) -> Transaction {
  let PluggableLogicTestCase { is_withdrawal_script_validated } = test_case

  mocktail_tx()
    |> script_withdrawal(
        is_withdrawal_script_validated,
        mock_pluggable_logic,
        0,
      )
    |> complete()
}

fn run_pluggable_logic(test_case: PluggableLogicTestCase) -> Bool {
  let tx = mock_pluggable_logic_tx(test_case)
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_oracle_datum),
    PluggableLogic,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== PluggableLogic Tests ==========

test s0_spend_success_pluggable_logic() {
  run_pluggable_logic(default_pluggable_logic_test_case())
}

test s0_spend_fail_pluggable_logic_without_withdrawal_script() {
  let test_case =
    PluggableLogicTestCase { is_withdrawal_script_validated: False }
  !run_pluggable_logic(test_case)
}

// ========== UpdateConfig Test Case ==========

type UpdateConfigTestCase {
  is_hydra_signer_1_signed: Bool,
  is_hydra_signer_2_signed: Bool,
  is_hydra_signer_3_signed: Bool,
  is_total_shares_unchanged: Bool,
  is_operator_shares_unchanged: Bool,
  is_total_deposited_unchanged: Bool,
  is_merkle_root_unchanged: Bool,
  is_fee_collected_unchanged: Bool,
  is_charge_percentage_valid: Bool,
}

fn default_update_config_test_case() -> UpdateConfigTestCase {
  UpdateConfigTestCase {
    is_hydra_signer_1_signed: True,
    is_hydra_signer_2_signed: True,
    is_hydra_signer_3_signed: True,
    is_total_shares_unchanged: True,
    is_operator_shares_unchanged: True,
    is_total_deposited_unchanged: True,
    is_merkle_root_unchanged: True,
    is_fee_collected_unchanged: True,
    is_charge_percentage_valid: True,
  }
}

fn mock_update_config_output_datum(
  test_case: UpdateConfigTestCase,
) -> VaultOracleDatum {
  let UpdateConfigTestCase {
    is_total_shares_unchanged,
    is_operator_shares_unchanged,
    is_total_deposited_unchanged,
    is_merkle_root_unchanged,
    is_fee_collected_unchanged,
    is_charge_percentage_valid,
    ..
  } = test_case

  let total_shares =
    if is_total_shares_unchanged {
      mock_vault_oracle_datum.total_shares
    } else {
      mock_vault_oracle_datum.total_shares + 1
    }

  let operator_shares =
    if is_operator_shares_unchanged {
      mock_vault_oracle_datum.operator_shares
    } else {
      mock_vault_oracle_datum.operator_shares + 1
    }

  let total_deposited =
    if is_total_deposited_unchanged {
      mock_vault_oracle_datum.total_deposited
    } else {
      mock_vault_oracle_datum.total_deposited + 1
    }

  let shares_merkle_root =
    if is_merkle_root_unchanged {
      mock_vault_oracle_datum.shares_merkle_root
    } else {
      // Different hash
      #"1111111111111111111111111111111111111111111111111111111111111111"
    }

  let total_fee_share_collected =
    if is_fee_collected_unchanged {
      mock_vault_oracle_datum.total_fee_share_collected
    } else {
      mock_vault_oracle_datum.total_fee_share_collected + 1
    }

  let operator_fee_rate_bp =
    if is_charge_percentage_valid {
      50
    } else {
      101
    }

  VaultOracleDatum {
    ..mock_vault_oracle_datum,
    total_shares: total_shares,
    operator_shares: operator_shares,
    total_deposited: total_deposited,
    shares_merkle_root: shares_merkle_root,
    total_fee_share_collected: total_fee_share_collected,
    operator_fee_rate_bp: operator_fee_rate_bp,
  }
}

fn mock_update_config_tx(test_case: UpdateConfigTestCase) -> Transaction {
  let UpdateConfigTestCase {
    is_hydra_signer_1_signed,
    is_hydra_signer_2_signed,
    is_hydra_signer_3_signed,
    ..
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_value = from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let output_datum = mock_update_config_output_datum(test_case)

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, vault_value, vault_oracle_address)
    |> tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> tx_out(True, vault_oracle_address, vault_value)
    |> tx_out_inline_datum(True, output_datum)
    |> required_signer_hash(is_hydra_signer_1_signed, mock_hydra_signer_1)
    |> required_signer_hash(is_hydra_signer_2_signed, mock_hydra_signer_2)
    |> required_signer_hash(is_hydra_signer_3_signed, mock_hydra_signer_3)
    |> complete()
}

fn run_update_config(test_case: UpdateConfigTestCase) -> Bool {
  let tx = mock_update_config_tx(test_case)
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_oracle_datum),
    UpdateConfig,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== UpdateConfig Tests ==========

test s0_spend_success_update_config() {
  run_update_config(default_update_config_test_case())
}

test s0_spend_fail_update_config_without_signer_1() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_hydra_signer_1_signed: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_without_signer_2() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_hydra_signer_2_signed: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_without_signer_3() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_hydra_signer_3_signed: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_when_total_shares_changed() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_total_shares_unchanged: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_when_operator_shares_changed() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_operator_shares_unchanged: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_when_total_deposited_changed() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_total_deposited_unchanged: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_when_merkle_root_changed() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_merkle_root_unchanged: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_when_fee_collected_changed() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_fee_collected_unchanged: False,
    }
  !run_update_config(test_case)
}

test s0_spend_fail_update_config_with_invalid_charge_percentage() {
  let test_case =
    UpdateConfigTestCase {
      ..default_update_config_test_case(),
      is_charge_percentage_valid: False,
    }
  !run_update_config(test_case)
}
