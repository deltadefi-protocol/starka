use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx,
  required_signer_hash, tx_in, tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_hydra_signer_1, mock_hydra_signer_2, mock_hydra_signer_3,
  mock_initial_utxo, mock_l1_deposit_intent_script_hash,
  mock_l1_withdrawal_intent_script_hash, mock_l2_deposit_intent_script_hash,
  mock_l2_withdrawal_intent_script_hash, mock_vault_config_datum, mock_vault_nft,
  mock_vault_oracle_datum,
}
use types.{
  BurnIntent, BurnIntentL2, BurnVault, CancelIntent, CancelIntentL2, HydraCommit,
  HydraDecommit, ProcessL1Deposit, ProcessL1Withdrawal, ProcessL2Deposit,
  ProcessL2Withdrawal, UpdateConfig, VaultOracleDatum, VaultOracleSpendRedeemer,
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

fn mock_process_l1_intent_tx(
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

fn mock_process_l2_intent_tx(
  intent_script_hash: ByteArray,
  test_case: ProcessIntentTestCase,
) -> Transaction {
  let ProcessIntentTestCase { is_intent_burnt, is_burn_intent_redeemer } =
    test_case

  let burn_redeemer: Data =
    if is_burn_intent_redeemer {
      BurnIntentL2
    } else {
      // Use some other redeemer that's not BurnIntentL2
      CancelIntentL2
    }

  mocktail_tx()
    |> mint(is_intent_burnt, -1, intent_script_hash, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(intent_script_hash), burn_redeemer))
}

fn run_process_l1_intent(
  intent_script_hash: ByteArray,
  redeemer: VaultOracleSpendRedeemer,
  test_case: ProcessIntentTestCase,
) -> Bool {
  let tx = mock_process_l1_intent_tx(intent_script_hash, test_case)
  let datum: Data = mock_vault_oracle_datum
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

fn run_process_l2_intent(
  intent_script_hash: ByteArray,
  redeemer: VaultOracleSpendRedeemer,
  test_case: ProcessIntentTestCase,
) -> Bool {
  let tx = mock_process_l2_intent_tx(intent_script_hash, test_case)
  let datum: Data = mock_vault_oracle_datum
  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== ProcessL1Deposit Tests ==========

test s0_spend_success_process_l1_deposit() {
  run_process_l1_intent(
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
  !run_process_l1_intent(
    mock_l1_deposit_intent_script_hash,
    ProcessL1Deposit,
    test_case,
  )
}

// ========== ProcessL1Withdrawal Tests ==========

test s0_spend_success_process_l1_withdrawal() {
  run_process_l1_intent(
    mock_l1_withdrawal_intent_script_hash,
    ProcessL1Withdrawal,
    default_process_intent_test_case(),
  )
}

// ========== ProcessL2Deposit Tests ==========

test s0_spend_success_process_l2_deposit() {
  run_process_l2_intent(
    mock_l2_deposit_intent_script_hash,
    ProcessL2Deposit,
    default_process_intent_test_case(),
  )
}

// ========== ProcessL2Withdrawal Tests ==========

test s0_spend_success_process_l2_withdrawal() {
  run_process_l2_intent(
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
  let datum: Data = mock_vault_oracle_datum

  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
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
  let datum: Data = mock_vault_oracle_datum

  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
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

// ========== UpdateConfig Test Case (State Oracle) ==========
// When spending VaultOracleDatum (State Oracle), state CAN change.
// Only charge percentage validation applies.

type UpdateConfigStateOracleTestCase {
  is_hydra_signer_1_signed: Bool,
  is_hydra_signer_2_signed: Bool,
  is_hydra_signer_3_signed: Bool,
  is_charge_percentage_valid: Bool,
}

fn default_update_config_state_oracle_test_case() -> UpdateConfigStateOracleTestCase {
  UpdateConfigStateOracleTestCase {
    is_hydra_signer_1_signed: True,
    is_hydra_signer_2_signed: True,
    is_hydra_signer_3_signed: True,
    is_charge_percentage_valid: True,
  }
}

fn mock_update_config_state_oracle_output_datum(
  test_case: UpdateConfigStateOracleTestCase,
) -> VaultOracleDatum {
  let UpdateConfigStateOracleTestCase { is_charge_percentage_valid, .. } =
    test_case

  let operator_fee_rate_bp =
    if is_charge_percentage_valid {
      50
    } else {
      101
    }

  // State can change when spending State Oracle
  VaultOracleDatum {
    ..mock_vault_oracle_datum,
    total_shares: mock_vault_oracle_datum.total_shares + 100,
    operator_shares: mock_vault_oracle_datum.operator_shares + 10,
    operator_fee_rate_bp: operator_fee_rate_bp,
  }
}

fn mock_update_config_state_oracle_tx(
  test_case: UpdateConfigStateOracleTestCase,
) -> Transaction {
  let UpdateConfigStateOracleTestCase {
    is_hydra_signer_1_signed,
    is_hydra_signer_2_signed,
    is_hydra_signer_3_signed,
    ..
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_value = from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let output_datum = mock_update_config_state_oracle_output_datum(test_case)

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

fn run_update_config_state_oracle(
  test_case: UpdateConfigStateOracleTestCase,
) -> Bool {
  let tx = mock_update_config_state_oracle_tx(test_case)
  let datum: Data = mock_vault_oracle_datum

  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
    UpdateConfig,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== UpdateConfig State Oracle Tests ==========

test s0_spend_success_update_config_state_oracle() {
  run_update_config_state_oracle(default_update_config_state_oracle_test_case())
}

test s0_spend_fail_update_config_state_oracle_without_signer_1() {
  let test_case =
    UpdateConfigStateOracleTestCase {
      ..default_update_config_state_oracle_test_case(),
      is_hydra_signer_1_signed: False,
    }
  !run_update_config_state_oracle(test_case)
}

test s0_spend_fail_update_config_state_oracle_without_signer_2() {
  let test_case =
    UpdateConfigStateOracleTestCase {
      ..default_update_config_state_oracle_test_case(),
      is_hydra_signer_2_signed: False,
    }
  !run_update_config_state_oracle(test_case)
}

test s0_spend_fail_update_config_state_oracle_without_signer_3() {
  let test_case =
    UpdateConfigStateOracleTestCase {
      ..default_update_config_state_oracle_test_case(),
      is_hydra_signer_3_signed: False,
    }
  !run_update_config_state_oracle(test_case)
}

test s0_spend_fail_update_config_state_oracle_with_invalid_charge_percentage() {
  let test_case =
    UpdateConfigStateOracleTestCase {
      ..default_update_config_state_oracle_test_case(),
      is_charge_percentage_valid: False,
    }
  !run_update_config_state_oracle(test_case)
}

// ========== UpdateConfig Test Case (Config Oracle) ==========
// When spending VaultConfig (Config Oracle), state fields in output must remain 0.

type UpdateConfigConfigOracleTestCase {
  is_hydra_signer_1_signed: Bool,
  is_hydra_signer_2_signed: Bool,
  is_hydra_signer_3_signed: Bool,
  is_charge_percentage_valid: Bool,
  is_state_zero: Bool,
}

fn default_update_config_config_oracle_test_case() -> UpdateConfigConfigOracleTestCase {
  UpdateConfigConfigOracleTestCase {
    is_hydra_signer_1_signed: True,
    is_hydra_signer_2_signed: True,
    is_hydra_signer_3_signed: True,
    is_charge_percentage_valid: True,
    is_state_zero: True,
  }
}

fn mock_update_config_config_oracle_output_datum(
  test_case: UpdateConfigConfigOracleTestCase,
) -> VaultOracleDatum {
  let UpdateConfigConfigOracleTestCase {
    is_charge_percentage_valid,
    is_state_zero,
    ..
  } = test_case

  let operator_fee_rate_bp =
    if is_charge_percentage_valid {
      50
    } else {
      101
    }

  // State fields must be 0 when spending Config Oracle
  let (
    total_shares,
    operator_shares,
    total_deposited,
    shares_merkle_root,
    total_fee_share_collected,
  ) =
    if is_state_zero {
      (0, 0, 0, "", 0)
    } else {
      // Non-zero state should fail
      (100, 10, 1000, "", 5)
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

fn mock_update_config_config_oracle_tx(
  test_case: UpdateConfigConfigOracleTestCase,
) -> Transaction {
  let UpdateConfigConfigOracleTestCase {
    is_hydra_signer_1_signed,
    is_hydra_signer_2_signed,
    is_hydra_signer_3_signed,
    ..
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_value = from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let output_datum = mock_update_config_config_oracle_output_datum(test_case)

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, vault_value, vault_oracle_address)
    |> tx_in_inline_datum(True, mock_vault_config_datum)
    |> tx_out(True, vault_oracle_address, vault_value)
    |> tx_out_inline_datum(True, output_datum)
    |> required_signer_hash(is_hydra_signer_1_signed, mock_hydra_signer_1)
    |> required_signer_hash(is_hydra_signer_2_signed, mock_hydra_signer_2)
    |> required_signer_hash(is_hydra_signer_3_signed, mock_hydra_signer_3)
    |> complete()
}

fn run_update_config_config_oracle(
  test_case: UpdateConfigConfigOracleTestCase,
) -> Bool {
  let tx = mock_update_config_config_oracle_tx(test_case)
  let datum: Data = mock_vault_config_datum

  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
    UpdateConfig,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== UpdateConfig Config Oracle Tests ==========

test s0_spend_success_update_config_config_oracle() {
  run_update_config_config_oracle(
    default_update_config_config_oracle_test_case(),
  )
}

test s0_spend_fail_update_config_config_oracle_without_signer_1() {
  let test_case =
    UpdateConfigConfigOracleTestCase {
      ..default_update_config_config_oracle_test_case(),
      is_hydra_signer_1_signed: False,
    }
  !run_update_config_config_oracle(test_case)
}

test s0_spend_fail_update_config_config_oracle_with_invalid_charge_percentage() {
  let test_case =
    UpdateConfigConfigOracleTestCase {
      ..default_update_config_config_oracle_test_case(),
      is_charge_percentage_valid: False,
    }
  !run_update_config_config_oracle(test_case)
}

test s0_spend_fail_update_config_config_oracle_with_nonzero_state() {
  let test_case =
    UpdateConfigConfigOracleTestCase {
      ..default_update_config_config_oracle_test_case(),
      is_state_zero: False,
    }
  !run_update_config_config_oracle(test_case)
}

// ========== BurnVault Test Case ==========
// BurnVault allows spending oracle when NFTs are being burnt.

type BurnVaultTestCase {
  is_oracle_burnt: Bool,
}

fn default_burn_vault_test_case() -> BurnVaultTestCase {
  BurnVaultTestCase { is_oracle_burnt: True }
}

fn mock_burn_vault_tx(test_case: BurnVaultTestCase) -> Transaction {
  let BurnVaultTestCase { is_oracle_burnt } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_value = from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  // Both oracles must be burnt (-2 total)
  let burn_quantity =
    if is_oracle_burnt {
      -2
    } else {
      -1
    }

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, vault_value, vault_oracle_address)
    |> tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> mint(True, burn_quantity, mock_vault_nft, "")
    |> complete()
}

fn run_burn_vault(test_case: BurnVaultTestCase) -> Bool {
  let tx = mock_burn_vault_tx(test_case)
  let datum: Data = mock_vault_oracle_datum

  vault_oracle.vault_oracle.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(datum),
    BurnVault,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== BurnVault Tests ==========

test s0_spend_success_burn_vault() {
  run_burn_vault(default_burn_vault_test_case())
}

test s0_spend_fail_burn_vault_without_burning() {
  let test_case = BurnVaultTestCase { is_oracle_burnt: False }
  !run_burn_vault(test_case)
}
