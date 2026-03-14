use cardano/address.{from_script, from_verification_key}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, required_signer_hash, tx_in, tx_in_inline_datum,
  tx_out, tx_out_inline_datum,
}
use tests/utils.{
  compute_mpf_root_single_insert, mock_app_oracle, mock_app_oracle_address,
  mock_app_oracle_datum, mock_create_vault_deposit_m_value,
  mock_create_vault_initial_shares, mock_create_vault_message,
  mock_create_vault_signatures, mock_create_vault_total_deposited,
  mock_initial_utxo, mock_l1_deposit_intent_script_hash,
  mock_l1_withdrawal_intent_script_hash, mock_l2_deposit_intent_script_hash,
  mock_l2_withdrawal_intent_script_hash, mock_node_pub_keys, mock_operation_key,
  mock_operator_key, mock_pluggable_logic, mock_vault_nft,
  mock_vault_oracle_datum, mock_vault_script_hash,
  mock_vault_stake_rotation_script_hash, null_hash,
}
use types.{CloseVault, CreateVault, VaultOracleDatum}
use vault_oracle/spend_mint as vault_oracle

// ========== CreateVault Test Case ==========

type CreateVaultTestCase {
  is_initial_utxo_consumed: Bool,
  is_oracle_nft_minted: Bool,
  is_app_oracle_referenced: Bool,
  is_hydra_keys_valid: Bool,
  is_total_shares_correct: Bool,
  is_operator_shares_correct: Bool,
  is_total_deposited_correct: Bool,
  is_shares_equal_deposited: Bool,
  is_merkle_root_correct: Bool,
  is_charge_percentage_valid: Bool,
  is_active_true: Bool,
  is_fee_collected_zero: Bool,
  is_deposit_in_vault: Bool,
  is_operator_signed: Bool,
  is_operation_signed: Bool,
}

fn default_create_vault_test_case() -> CreateVaultTestCase {
  CreateVaultTestCase {
    is_initial_utxo_consumed: True,
    is_oracle_nft_minted: True,
    is_app_oracle_referenced: True,
    is_hydra_keys_valid: True,
    is_total_shares_correct: True,
    is_operator_shares_correct: True,
    is_total_deposited_correct: True,
    is_shares_equal_deposited: True,
    is_merkle_root_correct: True,
    is_charge_percentage_valid: True,
    is_active_true: True,
    is_fee_collected_zero: True,
    is_deposit_in_vault: True,
    is_operator_signed: True,
    is_operation_signed: True,
  }
}

fn mock_create_vault_datum(test_case: CreateVaultTestCase) -> VaultOracleDatum {
  let CreateVaultTestCase {
    is_hydra_keys_valid,
    is_total_shares_correct,
    is_operator_shares_correct,
    is_total_deposited_correct,
    is_shares_equal_deposited,
    is_merkle_root_correct,
    is_charge_percentage_valid,
    is_active_true,
    is_fee_collected_zero,
    ..
  } = test_case

  // Compute correct merkle root
  let operator_address = from_verification_key(mock_operator_key)
  let correct_root =
    compute_mpf_root_single_insert(
      operator_address,
      mock_create_vault_initial_shares,
      mock_create_vault_total_deposited,
    )

  let total_shares =
    if is_total_shares_correct {
      mock_create_vault_initial_shares
    } else {
      mock_create_vault_initial_shares + 1
    }

  let operator_shares =
    if is_operator_shares_correct {
      mock_create_vault_initial_shares
    } else {
      mock_create_vault_initial_shares - 1
    }

  let total_deposited =
    if is_total_deposited_correct {
      mock_create_vault_total_deposited
    } else {
      mock_create_vault_total_deposited + 100
    }

  // For genesis, initial_shares must equal total_deposited
  let adjusted_total_shares =
    if !is_shares_equal_deposited {
      total_deposited + 1
    } else {
      total_shares
    }

  let shares_merkle_root =
    if is_merkle_root_correct {
      correct_root
    } else {
      null_hash
    }

  let operator_charge_percentage =
    if is_charge_percentage_valid {
      10
    } else {
      101
    }

  let is_active =
    if is_active_true {
      True
    } else {
      False
    }

  let total_fee_collected =
    if is_fee_collected_zero {
      0
    } else {
      100
    }

  let hydra_node_pub_keys =
    if is_hydra_keys_valid {
      mock_node_pub_keys
    } else {
      // Use different keys that don't match app_oracle signers
      [
        #"0000000000000000000000000000000000000000000000000000000000000001",
        #"0000000000000000000000000000000000000000000000000000000000000002",
        #"0000000000000000000000000000000000000000000000000000000000000003",
      ]
    }

  VaultOracleDatum {
    app_oracle: mock_app_oracle,
    vault_script_hash: mock_vault_script_hash,
    l1_deposit_intent_script_hash: mock_l1_deposit_intent_script_hash,
    l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
    l2_deposit_intent_script_hash: mock_l2_deposit_intent_script_hash,
    l2_withdrawal_intent_script_hash: mock_l2_withdrawal_intent_script_hash,
    pluggable_logic: mock_pluggable_logic,
    vault_stake_rotation_script_hash: mock_vault_stake_rotation_script_hash,
    operator_key: mock_operator_key,
    operator_charge_percentage,
    operator_min_deposit_percentage: 10,
    hydra_node_pub_keys,
    is_active,
    total_shares: adjusted_total_shares,
    operator_shares,
    total_deposited,
    shares_merkle_root,
    total_fee_collected,
  }
}

fn mock_create_vault_tx(test_case: CreateVaultTestCase) -> Transaction {
  let CreateVaultTestCase {
    is_initial_utxo_consumed,
    is_oracle_nft_minted,
    is_app_oracle_referenced,
    is_deposit_in_vault,
    is_operator_signed,
    is_operation_signed,
    ..
  } = test_case

  let vault_datum = mock_create_vault_datum(test_case)
  let vault_nft_policy = mock_vault_nft

  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)
  let vault_oracle_output_value =
    from_asset(vault_nft_policy, "", 1) |> add("", "", 2_000_000)

  let vault_output_value =
    if is_deposit_in_vault {
      from_asset_list(mock_create_vault_deposit_m_value)
    } else {
      from_asset("", "", 1)
    }

  // Initial utxo index - use 99,0 to match mock_initial_utxo, or different if not consumed
  let initial_utxo_index =
    if is_initial_utxo_consumed {
      0
    } else {
      999
    }

  mocktail_tx()
    // App oracle reference input
    |> ref_tx_in(
        is_app_oracle_referenced,
        mock_tx_hash(2),
        0,
        app_oracle_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_referenced, mock_app_oracle_datum)
    // Initial UTxO input (one-shot) - must match mock_initial_utxo = mock_utxo_ref(99, 0)
    |> tx_in(
        True,
        mock_tx_hash(99),
        initial_utxo_index,
        from_asset("", "", 2_000_000),
        mock_pub_key_address(0, None),
      )
    // Mint vault oracle NFT
    |> mint(is_oracle_nft_minted, 1, vault_nft_policy, "")
    // Vault oracle output
    |> tx_out(True, from_script(vault_nft_policy), vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_datum)
    // Initial deposit to vault script
    |> tx_out(True, from_script(mock_vault_script_hash), vault_output_value)
    // Signatures
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> required_signer_hash(is_operation_signed, mock_operation_key)
    |> complete()
}

fn run_create_vault(test_case: CreateVaultTestCase) -> Bool {
  let redeemer =
    CreateVault {
      initial_deposit: mock_create_vault_deposit_m_value,
      initial_shares: mock_create_vault_initial_shares,
      prices_message: mock_create_vault_message,
      signatures: mock_create_vault_signatures,
      initial_shares_proof: [],
    }
  let tx = mock_create_vault_tx(test_case)
  vault_oracle.vault_oracle.mint(
    mock_initial_utxo,
    mock_app_oracle,
    redeemer,
    mock_vault_nft,
    tx,
  )
}

// ========== CreateVault Tests ==========

test s0_mint_success_create_vault() {
  let test_case = default_create_vault_test_case()
  run_create_vault(test_case)
}

test s0_mint_fail_create_vault_without_initial_utxo_consumed() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_initial_utxo_consumed: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_without_oracle_nft_minted() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_oracle_nft_minted: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_without_app_oracle_referenced() fail {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_app_oracle_referenced: False,
    }
  run_create_vault(test_case)
}

test s0_mint_fail_create_vault_with_invalid_hydra_keys() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_hydra_keys_valid: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_with_incorrect_total_shares() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_total_shares_correct: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_with_incorrect_operator_shares() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_operator_shares_correct: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_with_incorrect_total_deposited() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_total_deposited_correct: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_when_shares_not_equal_deposited() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_shares_equal_deposited: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_with_incorrect_merkle_root() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_merkle_root_correct: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_with_invalid_charge_percentage() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_charge_percentage_valid: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_when_not_active() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_active_true: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_when_fee_collected_not_zero() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_fee_collected_zero: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_without_deposit_in_vault() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_deposit_in_vault: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_without_operator_signed() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_operator_signed: False,
    }
  !run_create_vault(test_case)
}

test s0_mint_fail_create_vault_without_operation_signed() {
  let test_case =
    CreateVaultTestCase {
      ..default_create_vault_test_case(),
      is_operation_signed: False,
    }
  !run_create_vault(test_case)
}

// ========== CloseVault Test Case ==========

type CloseVaultTestCase {
  is_oracle_input_present: Bool,
  is_oracle_nft_burnt: Bool,
  is_app_oracle_referenced: Bool,
  is_total_shares_zero: Bool,
  is_merkle_empty: Bool,
  is_operator_signed: Bool,
  is_operation_signed: Bool,
}

fn default_close_vault_test_case() -> CloseVaultTestCase {
  CloseVaultTestCase {
    is_oracle_input_present: True,
    is_oracle_nft_burnt: True,
    is_app_oracle_referenced: True,
    is_total_shares_zero: True,
    is_merkle_empty: True,
    is_operator_signed: True,
    is_operation_signed: True,
  }
}

fn mock_close_vault_datum(test_case: CloseVaultTestCase) -> VaultOracleDatum {
  let CloseVaultTestCase { is_total_shares_zero, is_merkle_empty, .. } =
    test_case

  let total_shares =
    if is_total_shares_zero {
      0
    } else {
      1000
    }

  let shares_merkle_root =
    if is_merkle_empty {
      null_hash
    } else {
      // Non-empty root
      compute_mpf_root_single_insert(
        from_verification_key(mock_operator_key),
        1000,
        1000,
      )
    }

  VaultOracleDatum {
    ..mock_vault_oracle_datum,
    total_shares: total_shares,
    operator_shares: 0,
    total_deposited: 0,
    shares_merkle_root: shares_merkle_root,
    total_fee_collected: 0,
  }
}

fn mock_close_vault_tx(test_case: CloseVaultTestCase) -> Transaction {
  let CloseVaultTestCase {
    is_oracle_input_present,
    is_oracle_nft_burnt,
    is_app_oracle_referenced,
    is_operator_signed,
    is_operation_signed,
    ..
  } = test_case

  let vault_nft_policy = mock_vault_nft
  let close_vault_datum = mock_close_vault_datum(test_case)

  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)
  let vault_oracle_input_value =
    from_asset(vault_nft_policy, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // App oracle reference input
    |> ref_tx_in(
        is_app_oracle_referenced,
        mock_tx_hash(2),
        0,
        app_oracle_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_referenced, mock_app_oracle_datum)
    // Vault oracle input
    |> tx_in(
        is_oracle_input_present,
        mock_tx_hash(1),
        0,
        vault_oracle_input_value,
        from_script(vault_nft_policy),
      )
    |> tx_in_inline_datum(is_oracle_input_present, close_vault_datum)
    // Burn vault oracle NFT
    |> mint(is_oracle_nft_burnt, -1, vault_nft_policy, "")
    // Signatures
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> required_signer_hash(is_operation_signed, mock_operation_key)
    |> complete()
}

fn run_close_vault(test_case: CloseVaultTestCase) -> Bool {
  let tx = mock_close_vault_tx(test_case)
  vault_oracle.vault_oracle.mint(
    mock_initial_utxo,
    mock_app_oracle,
    CloseVault,
    mock_vault_nft,
    tx,
  )
}

// ========== CloseVault Tests ==========

test s0_mint_success_close_vault() {
  let test_case = default_close_vault_test_case()
  run_close_vault(test_case)
}

test s0_mint_fail_close_vault_without_oracle_input() fail {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_oracle_input_present: False,
    }
  run_close_vault(test_case)
}

test s0_mint_fail_close_vault_without_nft_burnt() {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_oracle_nft_burnt: False,
    }
  !run_close_vault(test_case)
}

test s0_mint_fail_close_vault_without_app_oracle_referenced() fail {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_app_oracle_referenced: False,
    }
  run_close_vault(test_case)
}

test s0_mint_fail_close_vault_with_non_zero_total_shares() {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_total_shares_zero: False,
    }
  !run_close_vault(test_case)
}

test s0_mint_fail_close_vault_with_non_empty_merkle() {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_merkle_empty: False,
    }
  !run_close_vault(test_case)
}

test s0_mint_fail_close_vault_without_operator_signed() {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_operator_signed: False,
    }
  !run_close_vault(test_case)
}

test s0_mint_fail_close_vault_without_operation_signed() {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_operation_signed: False,
    }
  !run_close_vault(test_case)
}
