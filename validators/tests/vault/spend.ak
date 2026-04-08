use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx,
  ref_tx_in, ref_tx_in_inline_datum, script_withdrawal, tx_in,
  tx_in_inline_datum,
}
use tests/utils.{
  mock_app_deposit_request_token, mock_app_oracle, mock_app_oracle_address,
  mock_app_oracle_datum, mock_l1_withdrawal_intent_script_hash,
  mock_pluggable_logic, mock_vault_nft, mock_vault_oracle_datum,
  mock_vault_stake_rotation_script_hash,
}
use types.{
  BurnIntent, CancelIntent, DepositIntoDeltaDeFi, ProcessWithdrawal,
  StakeRotation, VaultPluggableLogic,
}
use vault/spend_withdrawal as vault

// ========== ProcessWithdrawal Test Case ==========

type ProcessWithdrawalTestCase {
  is_vault_oracle_inputed: Bool,
  is_intent_burnt: Bool,
  is_burn_intent_redeemer: Bool,
}

fn default_process_withdrawal_test_case() -> ProcessWithdrawalTestCase {
  ProcessWithdrawalTestCase {
    is_vault_oracle_inputed: True,
    is_intent_burnt: True,
    is_burn_intent_redeemer: True,
  }
}

fn mock_process_withdrawal_tx(
  test_case: ProcessWithdrawalTestCase,
) -> Transaction {
  let ProcessWithdrawalTestCase {
    is_vault_oracle_inputed,
    is_intent_burnt,
    is_burn_intent_redeemer,
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  let burn_redeemer: Data =
    if is_burn_intent_redeemer {
      BurnIntent([], "", [], [])
    } else {
      CancelIntent
    }

  mocktail_tx()
    |> tx_in(
        is_vault_oracle_inputed,
        mock_tx_hash(1),
        0,
        vault_oracle_value,
        vault_oracle_address,
      )
    |> tx_in_inline_datum(is_vault_oracle_inputed, mock_vault_oracle_datum)
    |> mint(is_intent_burnt, -1, mock_l1_withdrawal_intent_script_hash, "")
    |> complete()
    |> add_redeemer(
        True,
        Pair(Mint(mock_l1_withdrawal_intent_script_hash), burn_redeemer),
      )
}

fn run_process_withdrawal(test_case: ProcessWithdrawalTestCase) -> Bool {
  let tx = mock_process_withdrawal_tx(test_case)
  vault.vault.spend(
    mock_vault_nft,
    None,
    ProcessWithdrawal,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== ProcessWithdrawal Tests ==========

test s1_spend_success_process_withdrawal() {
  run_process_withdrawal(default_process_withdrawal_test_case())
}

test s1_spend_fail_process_withdrawal_without_vault_oracle_inputed() fail {
  let test_case =
    ProcessWithdrawalTestCase {
      ..default_process_withdrawal_test_case(),
      is_vault_oracle_inputed: False,
    }
  run_process_withdrawal(test_case)
}

test s1_spend_fail_process_withdrawal_without_burn_intent_redeemer() {
  let test_case =
    ProcessWithdrawalTestCase {
      ..default_process_withdrawal_test_case(),
      is_burn_intent_redeemer: False,
    }
  !run_process_withdrawal(test_case)
}

// ========== DepositIntoDeltaDeFi Test Case ==========

type DepositIntoDeltaDeFiTestCase {
  is_vault_oracle_referenced: Bool,
  is_app_oracle_referenced: Bool,
  is_deposit_request_minted: Bool,
}

fn default_deposit_into_deltadefi_test_case() -> DepositIntoDeltaDeFiTestCase {
  DepositIntoDeltaDeFiTestCase {
    is_vault_oracle_referenced: True,
    is_app_oracle_referenced: True,
    is_deposit_request_minted: True,
  }
}

fn mock_deposit_into_deltadefi_tx(
  test_case: DepositIntoDeltaDeFiTestCase,
) -> Transaction {
  let DepositIntoDeltaDeFiTestCase {
    is_vault_oracle_referenced,
    is_app_oracle_referenced,
    is_deposit_request_minted,
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    |> ref_tx_in(
        is_vault_oracle_referenced,
        mock_tx_hash(1),
        0,
        vault_oracle_value,
        vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(
        is_vault_oracle_referenced,
        mock_vault_oracle_datum,
      )
    |> ref_tx_in(
        is_app_oracle_referenced,
        mock_tx_hash(2),
        0,
        app_oracle_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_referenced, mock_app_oracle_datum)
    |> mint(is_deposit_request_minted, 1, mock_app_deposit_request_token, "")
    |> complete()
}

fn run_deposit_into_deltadefi(test_case: DepositIntoDeltaDeFiTestCase) -> Bool {
  let tx = mock_deposit_into_deltadefi_tx(test_case)
  vault.vault.spend(
    mock_vault_nft,
    None,
    DepositIntoDeltaDeFi,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== DepositIntoDeltaDeFi Tests ==========

test s1_spend_success_deposit_into_deltadefi() {
  run_deposit_into_deltadefi(default_deposit_into_deltadefi_test_case())
}

test s1_spend_fail_deposit_into_deltadefi_without_vault_oracle_referenced() fail {
  let test_case =
    DepositIntoDeltaDeFiTestCase {
      ..default_deposit_into_deltadefi_test_case(),
      is_vault_oracle_referenced: False,
    }
  run_deposit_into_deltadefi(test_case)
}

test s1_spend_fail_deposit_into_deltadefi_without_app_oracle_referenced() fail {
  let test_case =
    DepositIntoDeltaDeFiTestCase {
      ..default_deposit_into_deltadefi_test_case(),
      is_app_oracle_referenced: False,
    }
  run_deposit_into_deltadefi(test_case)
}

test s1_spend_fail_deposit_into_deltadefi_without_deposit_request_minted() {
  let test_case =
    DepositIntoDeltaDeFiTestCase {
      ..default_deposit_into_deltadefi_test_case(),
      is_deposit_request_minted: False,
    }
  !run_deposit_into_deltadefi(test_case)
}

// ========== StakeRotation Test Case ==========

type StakeRotationTestCase {
  is_vault_oracle_referenced: Bool,
  is_withdrawal_script_validated: Bool,
}

fn default_stake_rotation_test_case() -> StakeRotationTestCase {
  StakeRotationTestCase {
    is_vault_oracle_referenced: True,
    is_withdrawal_script_validated: True,
  }
}

fn mock_stake_rotation_tx(test_case: StakeRotationTestCase) -> Transaction {
  let StakeRotationTestCase {
    is_vault_oracle_referenced,
    is_withdrawal_script_validated,
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    |> ref_tx_in(
        is_vault_oracle_referenced,
        mock_tx_hash(1),
        0,
        vault_oracle_value,
        vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(
        is_vault_oracle_referenced,
        mock_vault_oracle_datum,
      )
    |> script_withdrawal(
        is_withdrawal_script_validated,
        mock_vault_stake_rotation_script_hash,
        0,
      )
    |> complete()
}

fn run_stake_rotation(test_case: StakeRotationTestCase) -> Bool {
  let tx = mock_stake_rotation_tx(test_case)
  vault.vault.spend(
    mock_vault_nft,
    None,
    StakeRotation,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== StakeRotation Tests ==========

test s1_spend_success_stake_rotation() {
  run_stake_rotation(default_stake_rotation_test_case())
}

test s1_spend_fail_stake_rotation_without_vault_oracle_referenced() fail {
  let test_case =
    StakeRotationTestCase {
      ..default_stake_rotation_test_case(),
      is_vault_oracle_referenced: False,
    }
  run_stake_rotation(test_case)
}

test s1_spend_fail_stake_rotation_without_withdrawal_script() {
  let test_case =
    StakeRotationTestCase {
      ..default_stake_rotation_test_case(),
      is_withdrawal_script_validated: False,
    }
  !run_stake_rotation(test_case)
}

// ========== VaultPluggableLogic Test Case ==========

type VaultPluggableLogicTestCase {
  is_vault_oracle_referenced: Bool,
  is_withdrawal_script_validated: Bool,
}

fn default_vault_pluggable_logic_test_case() -> VaultPluggableLogicTestCase {
  VaultPluggableLogicTestCase {
    is_vault_oracle_referenced: True,
    is_withdrawal_script_validated: True,
  }
}

fn mock_vault_pluggable_logic_tx(
  test_case: VaultPluggableLogicTestCase,
) -> Transaction {
  let VaultPluggableLogicTestCase {
    is_vault_oracle_referenced,
    is_withdrawal_script_validated,
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    |> ref_tx_in(
        is_vault_oracle_referenced,
        mock_tx_hash(1),
        0,
        vault_oracle_value,
        vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(
        is_vault_oracle_referenced,
        mock_vault_oracle_datum,
      )
    |> script_withdrawal(
        is_withdrawal_script_validated,
        mock_pluggable_logic,
        0,
      )
    |> complete()
}

fn run_vault_pluggable_logic(test_case: VaultPluggableLogicTestCase) -> Bool {
  let tx = mock_vault_pluggable_logic_tx(test_case)
  vault.vault.spend(
    mock_vault_nft,
    None,
    VaultPluggableLogic,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== VaultPluggableLogic Tests ==========

test s1_spend_success_vault_pluggable_logic() {
  run_vault_pluggable_logic(default_vault_pluggable_logic_test_case())
}

test s1_spend_fail_vault_pluggable_logic_without_vault_oracle_referenced() fail {
  let test_case =
    VaultPluggableLogicTestCase {
      ..default_vault_pluggable_logic_test_case(),
      is_vault_oracle_referenced: False,
    }
  run_vault_pluggable_logic(test_case)
}

test s1_spend_fail_vault_pluggable_logic_without_withdrawal_script() {
  let test_case =
    VaultPluggableLogicTestCase {
      ..default_vault_pluggable_logic_test_case(),
      is_withdrawal_script_validated: False,
    }
  !run_vault_pluggable_logic(test_case)
}
