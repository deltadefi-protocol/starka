use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, required_signer_hash, tx_in, tx_in_inline_datum,
  tx_out, tx_out_inline_datum,
}
use tests/utils.{
  compute_mpf_root_single_insert, mock_app_oracle, mock_app_oracle_address,
  mock_app_oracle_datum, mock_initial_utxo, mock_l1_deposit_intent_script_hash,
  mock_l1_withdrawal_intent_script_hash, mock_l2_deposit_intent_script_hash,
  mock_l2_withdrawal_intent_script_hash, mock_node_pub_keys, mock_operation_key,
  mock_operator_account, mock_operator_inner_account, mock_operator_key,
  mock_pluggable_logic, mock_vault_config_datum, mock_vault_nft,
  mock_vault_oracle_datum, mock_vault_script_hash,
  mock_vault_stake_rotation_script_hash, null_hash,
}
use types.{CloseVault, MintVault, VaultConfig, VaultOracleDatum}
use vault_oracle/spend_mint as vault_oracle

// ========== MintVault Test Case ==========
// MintVault is a split oracle minting policy:
// - Consume initial_utxo (one-shot guarantee)
// - Mint exactly 2 NFTs (same token name, distinguished by datum type)
// - Output Config Oracle (VaultConfig) and State Oracle (VaultOracleDatum)
// - State Oracle: all state fields = 0, shares_merkle_root = null_hash
// - Config fields must match between both datums
// - No signatures required (anyone can create a vault)

type MintVaultTestCase {
  is_initial_utxo_consumed: Bool,
  is_oracle_nft_minted: Bool,
  is_config_output_present: Bool,
  is_total_shares_zero: Bool,
  is_operator_shares_zero: Bool,
  is_total_deposited_zero: Bool,
  is_merkle_root_empty: Bool,
  is_fee_collected_zero: Bool,
  is_charge_percentage_valid: Bool,
  is_app_oracle_correct: Bool,
  is_app_oracle_referenced: Bool,
  is_hydra_keys_valid: Bool,
  is_config_matching: Bool,
}

fn default_mint_vault_test_case() -> MintVaultTestCase {
  MintVaultTestCase {
    is_initial_utxo_consumed: True,
    is_oracle_nft_minted: True,
    is_config_output_present: True,
    is_total_shares_zero: True,
    is_operator_shares_zero: True,
    is_total_deposited_zero: True,
    is_merkle_root_empty: True,
    is_fee_collected_zero: True,
    is_charge_percentage_valid: True,
    is_app_oracle_correct: True,
    is_app_oracle_referenced: True,
    is_hydra_keys_valid: True,
    is_config_matching: True,
  }
}

fn mock_mint_vault_datums(
  test_case: MintVaultTestCase,
) -> (VaultOracleDatum, VaultConfig) {
  let MintVaultTestCase {
    is_total_shares_zero,
    is_operator_shares_zero,
    is_total_deposited_zero,
    is_merkle_root_empty,
    is_fee_collected_zero,
    is_charge_percentage_valid,
    is_app_oracle_correct,
    is_hydra_keys_valid,
    is_config_matching,
    ..
  } = test_case

  let total_shares =
    if is_total_shares_zero {
      0
    } else {
      1000
    }

  let operator_shares =
    if is_operator_shares_zero {
      0
    } else {
      1000
    }

  let total_deposited =
    if is_total_deposited_zero {
      0
    } else {
      1000
    }

  let shares_merkle_root =
    if is_merkle_root_empty {
      mpf.root(mpf.empty)
    } else {
      // Non-empty root - use operator's Account as MPF key
      compute_mpf_root_single_insert(mock_operator_inner_account, 1000, 1000)
    }

  let total_fee_share_collected =
    if is_fee_collected_zero {
      0
    } else {
      100
    }

  let operator_fee_rate_bp =
    if is_charge_percentage_valid {
      10
    } else {
      10001
    }

  let app_oracle =
    if is_app_oracle_correct {
      mock_app_oracle
    } else {
      // Wrong app_oracle
      #"0000000000000000000000000000000000000000000000000000000000000000"
    }

  let hydra_node_pub_keys =
    if is_hydra_keys_valid {
      mock_node_pub_keys
    } else {
      // Wrong hydra keys - use different keys that won't match app_oracle
      [#"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
    }

  let vault_oracle_datum =
    VaultOracleDatum {
      app_oracle,
      vault_script_hash: mock_vault_script_hash,
      l1_deposit_intent_script_hash: mock_l1_deposit_intent_script_hash,
      l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
      l2_deposit_intent_script_hash: mock_l2_deposit_intent_script_hash,
      l2_withdrawal_intent_script_hash: mock_l2_withdrawal_intent_script_hash,
      pluggable_logic: mock_pluggable_logic,
      vault_stake_rotation_script_hash: mock_vault_stake_rotation_script_hash,
      operator_account: mock_operator_account,
      operator_fee_rate_bp,
      operator_min_deposit_rate_bp: 10,
      hydra_node_pub_keys,
      is_active: True,
      total_shares,
      operator_shares,
      total_deposited,
      shares_merkle_root,
      total_fee_share_collected,
    }

  // Config datum - should match state oracle's config fields
  let vault_config_datum =
    if is_config_matching {
      VaultConfig {
        app_oracle,
        l1_deposit_intent_script_hash: mock_l1_deposit_intent_script_hash,
        l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
        l2_deposit_intent_script_hash: mock_l2_deposit_intent_script_hash,
        l2_withdrawal_intent_script_hash: mock_l2_withdrawal_intent_script_hash,
        pluggable_logic: mock_pluggable_logic,
        operator_account: mock_operator_account,
        hydra_node_pub_keys,
      }
    } else {
      // Mismatched config - use different pluggable_logic
      VaultConfig {
        app_oracle,
        l1_deposit_intent_script_hash: mock_l1_deposit_intent_script_hash,
        l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
        l2_deposit_intent_script_hash: mock_l2_deposit_intent_script_hash,
        l2_withdrawal_intent_script_hash: mock_l2_withdrawal_intent_script_hash,
        pluggable_logic: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        operator_account: mock_operator_account,
        hydra_node_pub_keys,
      }
    }

  (vault_oracle_datum, vault_config_datum)
}

fn mock_mint_vault_tx(test_case: MintVaultTestCase) -> Transaction {
  let MintVaultTestCase {
    is_initial_utxo_consumed,
    is_oracle_nft_minted,
    is_config_output_present,
    is_app_oracle_referenced,
    ..
  } = test_case

  let (vault_oracle_datum, vault_config_datum) =
    mock_mint_vault_datums(test_case)
  let vault_nft_policy = mock_vault_nft

  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)
  let vault_oracle_output_value =
    from_asset(vault_nft_policy, "", 1) |> add("", "", 2_000_000)
  let vault_config_output_value =
    from_asset(vault_nft_policy, "", 1) |> add("", "", 2_000_000)

  // Initial utxo index - use 99,0 to match mock_initial_utxo, or different if not consumed
  let initial_utxo_index =
    if is_initial_utxo_consumed {
      0
    } else {
      999
    }

  // Mint 2 NFTs for split oracle (or 0 if not minting)
  let mint_quantity =
    if is_oracle_nft_minted {
      2
    } else {
      0
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
    // Mint vault oracle NFTs (2 for split oracle)
    |> mint(True, mint_quantity, vault_nft_policy, "")
    // Config Oracle output (VaultConfig datum)
    |> tx_out(
        is_config_output_present,
        from_script(vault_nft_policy),
        vault_config_output_value,
      )
    |> tx_out_inline_datum(is_config_output_present, vault_config_datum)
    // State Oracle output (VaultOracleDatum)
    |> tx_out(True, from_script(vault_nft_policy), vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_oracle_datum)
    |> complete()
}

fn run_mint_vault(test_case: MintVaultTestCase) -> Bool {
  let tx = mock_mint_vault_tx(test_case)
  vault_oracle.vault_oracle.mint(
    mock_initial_utxo,
    mock_app_oracle,
    MintVault,
    mock_vault_nft,
    tx,
  )
}

// ========== MintVault Tests ==========

test s0_mint_success_mint_vault() {
  let test_case = default_mint_vault_test_case()
  run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_without_initial_utxo_consumed() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_initial_utxo_consumed: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_without_oracle_nft_minted() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_oracle_nft_minted: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_non_zero_total_shares() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_total_shares_zero: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_non_zero_operator_shares() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_operator_shares_zero: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_non_zero_total_deposited() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_total_deposited_zero: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_non_empty_merkle_root() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_merkle_root_empty: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_non_zero_fee_collected() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_fee_collected_zero: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_invalid_charge_percentage() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_charge_percentage_valid: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_wrong_app_oracle() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_app_oracle_correct: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_without_app_oracle_referenced() fail {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_app_oracle_referenced: False,
    }
  run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_invalid_hydra_keys() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_hydra_keys_valid: False,
    }
  !run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_without_config_output() fail {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_config_output_present: False,
    }
  run_mint_vault(test_case)
}

test s0_mint_fail_mint_vault_with_mismatched_config() {
  let test_case =
    MintVaultTestCase {
      ..default_mint_vault_test_case(),
      is_config_matching: False,
    }
  !run_mint_vault(test_case)
}

// ========== CloseVault Test Case ==========

type CloseVaultTestCase {
  is_state_oracle_input_present: Bool,
  is_config_oracle_input_present: Bool,
  is_oracle_nft_burnt: Bool,
  is_app_oracle_referenced: Bool,
  is_total_shares_zero: Bool,
  is_merkle_empty: Bool,
  is_operator_signed: Bool,
  is_operation_signed: Bool,
}

fn default_close_vault_test_case() -> CloseVaultTestCase {
  CloseVaultTestCase {
    is_state_oracle_input_present: True,
    is_config_oracle_input_present: True,
    is_oracle_nft_burnt: True,
    is_app_oracle_referenced: True,
    is_total_shares_zero: True,
    is_merkle_empty: True,
    is_operator_signed: True,
    is_operation_signed: True,
  }
}

fn mock_close_vault_state_datum(
  test_case: CloseVaultTestCase,
) -> VaultOracleDatum {
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
      // Non-empty root - use operator's Account as MPF key
      compute_mpf_root_single_insert(mock_operator_inner_account, 1000, 1000)
    }

  VaultOracleDatum {
    ..mock_vault_oracle_datum,
    total_shares: total_shares,
    operator_shares: 0,
    total_deposited: 0,
    shares_merkle_root: shares_merkle_root,
    total_fee_share_collected: 0,
  }
}

fn mock_close_vault_tx(test_case: CloseVaultTestCase) -> Transaction {
  let CloseVaultTestCase {
    is_state_oracle_input_present,
    is_config_oracle_input_present,
    is_oracle_nft_burnt,
    is_app_oracle_referenced,
    is_operator_signed,
    is_operation_signed,
    ..
  } = test_case

  let vault_nft_policy = mock_vault_nft
  let close_vault_state_datum = mock_close_vault_state_datum(test_case)

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
    // Config Oracle input (VaultConfig datum)
    |> tx_in(
        is_config_oracle_input_present,
        mock_tx_hash(1),
        0,
        vault_oracle_input_value,
        from_script(vault_nft_policy),
      )
    |> tx_in_inline_datum(
        is_config_oracle_input_present,
        mock_vault_config_datum,
      )
    // State Oracle input (VaultOracleDatum)
    |> tx_in(
        is_state_oracle_input_present,
        mock_tx_hash(1),
        1,
        vault_oracle_input_value,
        from_script(vault_nft_policy),
      )
    |> tx_in_inline_datum(
        is_state_oracle_input_present,
        close_vault_state_datum,
      )
    // Burn both oracle NFTs (-2)
    |> mint(is_oracle_nft_burnt, -2, vault_nft_policy, "")
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

test s0_mint_fail_close_vault_without_state_oracle_input() fail {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_state_oracle_input_present: False,
    }
  run_close_vault(test_case)
}

test s0_mint_fail_close_vault_without_config_oracle_input() fail {
  let test_case =
    CloseVaultTestCase {
      ..default_close_vault_test_case(),
      is_config_oracle_input_present: False,
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
