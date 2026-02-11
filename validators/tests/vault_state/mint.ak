use cardano/address.{from_script, from_verification_key}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx,
  required_signer_hash, tx_in, tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_deposit_m_value, mock_lp_record_script_hash, mock_message,
  mock_operator_key, mock_signatures, mock_vault_oracle, mock_vault_oracle_datum,
  mock_vault_script_hash,
}
use types.{
  CloseVault, CreateVault, LPRecordDatum, VaultOracleDatum, VaultStateDatum,
}
use vault_state/spend_mint as vault_state

const mock_vault_state_policy_id = "mock_vault_state_policy"

const mock_initial_lp = 1_000_000

const mock_vault_cost = 3_641_915_286

// ==================== CreateVault ====================

type CreateVaultTestCase {
  is_vault_oracle_inputed: Bool,
  is_vault_oracle_updated: Bool,
  is_vault_state_minted: Bool,
  is_state_datum_correct: Bool,
  is_initial_deposit_sent: Bool,
  is_lp_record_minted: Bool,
  is_lp_record_datum_correct: Bool,
  is_operator_signed: Bool,
}

fn get_vault_oracle_inactive_datum() -> VaultOracleDatum {
  VaultOracleDatum { ..mock_vault_oracle_datum, is_active: False }
}

fn mock_create_vault_tx(test_case: CreateVaultTestCase) -> Transaction {
  let CreateVaultTestCase {
    is_vault_oracle_inputed,
    is_vault_oracle_updated,
    is_vault_state_minted,
    is_state_datum_correct,
    is_initial_deposit_sent,
    is_lp_record_minted,
    is_lp_record_datum_correct,
    is_operator_signed,
  } = test_case

  let vault_oracle_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let vault_oracle_input_datum = get_vault_oracle_inactive_datum()

  let vault_oracle_output_datum =
    if is_vault_oracle_updated {
      VaultOracleDatum { ..vault_oracle_input_datum, is_active: True }
    } else {
      vault_oracle_input_datum
    }

  let vault_state_datum =
    if is_state_datum_correct {
      VaultStateDatum {
        vault_oracle: mock_vault_oracle,
        total_lp: mock_initial_lp,
        operator_lp: mock_initial_lp,
        vault_cost: mock_vault_cost,
      }
    } else {
      VaultStateDatum {
        vault_oracle: mock_vault_oracle,
        total_lp: mock_initial_lp + 1,
        operator_lp: mock_initial_lp,
        vault_cost: mock_vault_cost,
      }
    }

  let lp_record_datum =
    if is_lp_record_datum_correct {
      LPRecordDatum {
        address: from_verification_key(mock_operator_key),
        lp: mock_initial_lp,
        cost: mock_vault_cost,
      }
    } else {
      LPRecordDatum {
        address: from_verification_key(mock_operator_key),
        lp: mock_initial_lp + 1,
        cost: mock_vault_cost,
      }
    }

  let deposit_value =
    if is_initial_deposit_sent {
      from_asset_list(mock_deposit_m_value)
    } else {
      from_asset("", "", 1)
    }

  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  let vault_state_value =
    from_asset(mock_vault_state_policy_id, "", 1) |> add("", "", 2_000_000)

  let lp_record_value =
    from_asset(mock_lp_record_script_hash, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // Vault oracle input (spending, not reference)
    |> tx_in(
        is_vault_oracle_inputed,
        mock_tx_hash(1),
        0,
        vault_oracle_value,
        from_script(mock_vault_oracle),
      )
    |> tx_in_inline_datum(is_vault_oracle_inputed, vault_oracle_input_datum)
    // Input matching utxo_ref in mock_message
    |> tx_in(
        True,
        mock_tx_hash(0),
        0,
        from_asset("", "", 2_000_000),
        mock_pub_key_address(0, None),
      )
    // App oracle reference input
    |> tx_in(
        True,
        mock_tx_hash(2),
        0,
        app_oracle_value,
        mock_app_oracle_address,
      )
    |> tx_in_inline_datum(True, mock_app_oracle_datum)
    // Vault oracle output
    |> tx_out(True, from_script(mock_vault_oracle), vault_oracle_value)
    |> tx_out_inline_datum(True, vault_oracle_output_datum)
    // Vault state output
    |> tx_out(True, from_script(mock_vault_state_policy_id), vault_state_value)
    |> tx_out_inline_datum(True, vault_state_datum)
    // LP record output
    |> tx_out(
        is_lp_record_minted,
        from_script(mock_lp_record_script_hash),
        lp_record_value,
      )
    |> tx_out_inline_datum(is_lp_record_minted, lp_record_datum)
    // Initial deposit to vault script
    |> tx_out(True, from_script(mock_vault_script_hash), deposit_value)
    // Mint vault state token + lp record token
    |> mint(is_vault_state_minted, 1, mock_vault_state_policy_id, "")
    |> mint(is_lp_record_minted, 1, mock_lp_record_script_hash, "")
    // Operator signature
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> complete()
}

fn run_create_vault(test_case: CreateVaultTestCase) -> Bool {
  let redeemer =
    CreateVault {
      initial_deposit: mock_deposit_m_value,
      initial_lp: mock_initial_lp,
      prices_message: mock_message,
      signatures: mock_signatures,
    }
  let tx = mock_create_vault_tx(test_case)

  vault_state.vault_state.mint(
    mock_vault_oracle,
    redeemer,
    mock_vault_state_policy_id,
    tx,
  )
}

test s1_mint_success_create_vault() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  run_create_vault(test_case)
}

test s1_mint_fail_create_vault_without_vault_oracle_inputed() fail {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: False,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  run_create_vault(test_case)
}

test s1_mint_fail_create_vault_without_vault_oracle_updated() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: False,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  !run_create_vault(test_case)
}

test s1_mint_fail_create_vault_without_vault_state_minted() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: False,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  !run_create_vault(test_case)
}

test s1_mint_fail_create_vault_with_incorrect_state_datum() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: False,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  !run_create_vault(test_case)
}

test s1_mint_fail_create_vault_without_initial_deposit_sent() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: False,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  !run_create_vault(test_case)
}

test s1_mint_fail_create_vault_without_lp_record_minted() fail {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: False,
      is_lp_record_datum_correct: True,
      is_operator_signed: True,
    }
  run_create_vault(test_case)
}

test s1_mint_fail_create_vault_with_incorrect_lp_record_datum() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: False,
      is_operator_signed: True,
    }
  !run_create_vault(test_case)
}

test s1_mint_fail_create_vault_without_operator_signed() {
  let test_case =
    CreateVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_minted: True,
      is_state_datum_correct: True,
      is_initial_deposit_sent: True,
      is_lp_record_minted: True,
      is_lp_record_datum_correct: True,
      is_operator_signed: False,
    }
  !run_create_vault(test_case)
}

// ==================== CloseVault ====================

type CloseVaultTestCase {
  is_vault_oracle_inputed: Bool,
  is_vault_oracle_updated: Bool,
  is_vault_state_inputed: Bool,
  is_vault_state_burnt: Bool,
  is_total_lp_zero: Bool,
  is_operator_signed: Bool,
}

fn mock_close_vault_tx(test_case: CloseVaultTestCase) -> Transaction {
  let CloseVaultTestCase {
    is_vault_oracle_inputed,
    is_vault_oracle_updated,
    is_vault_state_inputed,
    is_vault_state_burnt,
    is_total_lp_zero,
    is_operator_signed,
  } = test_case

  let vault_oracle_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let vault_oracle_output_datum =
    if is_vault_oracle_updated {
      VaultOracleDatum { ..mock_vault_oracle_datum, is_active: False }
    } else {
      mock_vault_oracle_datum
    }

  let vault_state_datum =
    VaultStateDatum {
      vault_oracle: mock_vault_oracle,
      total_lp: if is_total_lp_zero {
        0
      } else {
        1_000_000
      },
      operator_lp: 0,
      vault_cost: 0,
    }

  let vault_state_value =
    from_asset(mock_vault_state_policy_id, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // Vault oracle input
    |> tx_in(
        is_vault_oracle_inputed,
        mock_tx_hash(1),
        0,
        vault_oracle_value,
        from_script(mock_vault_oracle),
      )
    |> tx_in_inline_datum(is_vault_oracle_inputed, mock_vault_oracle_datum)
    // Vault state input
    |> tx_in(
        is_vault_state_inputed,
        mock_tx_hash(2),
        0,
        vault_state_value,
        from_script(mock_vault_state_policy_id),
      )
    |> tx_in_inline_datum(is_vault_state_inputed, vault_state_datum)
    // Vault oracle output
    |> tx_out(True, from_script(mock_vault_oracle), vault_oracle_value)
    |> tx_out_inline_datum(True, vault_oracle_output_datum)
    // Burn vault state token
    |> mint(is_vault_state_burnt, -1, mock_vault_state_policy_id, "")
    // Operator signature
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> complete()
}

fn run_close_vault(test_case: CloseVaultTestCase) -> Bool {
  let tx = mock_close_vault_tx(test_case)

  vault_state.vault_state.mint(
    mock_vault_oracle,
    CloseVault,
    mock_vault_state_policy_id,
    tx,
  )
}

test s1_mint_success_close_vault() {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_inputed: True,
      is_vault_state_burnt: True,
      is_total_lp_zero: True,
      is_operator_signed: True,
    }
  run_close_vault(test_case)
}

test s1_mint_fail_close_vault_without_vault_oracle_inputed() fail {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: False,
      is_vault_oracle_updated: True,
      is_vault_state_inputed: True,
      is_vault_state_burnt: True,
      is_total_lp_zero: True,
      is_operator_signed: True,
    }
  run_close_vault(test_case)
}

test s1_mint_fail_close_vault_without_vault_oracle_updated() {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: False,
      is_vault_state_inputed: True,
      is_vault_state_burnt: True,
      is_total_lp_zero: True,
      is_operator_signed: True,
    }
  !run_close_vault(test_case)
}

test s1_mint_fail_close_vault_without_vault_state_inputed() fail {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_inputed: False,
      is_vault_state_burnt: True,
      is_total_lp_zero: True,
      is_operator_signed: True,
    }
  run_close_vault(test_case)
}

test s1_mint_fail_close_vault_without_vault_state_burnt() {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_inputed: True,
      is_vault_state_burnt: False,
      is_total_lp_zero: True,
      is_operator_signed: True,
    }
  !run_close_vault(test_case)
}

test s1_mint_fail_close_vault_with_non_zero_total_lp() {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_inputed: True,
      is_vault_state_burnt: True,
      is_total_lp_zero: False,
      is_operator_signed: True,
    }
  !run_close_vault(test_case)
}

test s1_mint_fail_close_vault_without_operator_signed() {
  let test_case =
    CloseVaultTestCase {
      is_vault_oracle_inputed: True,
      is_vault_oracle_updated: True,
      is_vault_state_inputed: True,
      is_vault_state_burnt: True,
      is_total_lp_zero: True,
      is_operator_signed: False,
    }
  !run_close_vault(test_case)
}
