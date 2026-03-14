use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mock_tx_hash, mocktail_tx, ref_tx_in, ref_tx_in_inline_datum,
  required_signer_hash,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_operation_key, mock_operator_key, mock_vault_nft, mock_vault_oracle_datum,
}
use vault/spend_withdrawal as vault

// ========== Withdraw Test Case ==========

type WithdrawTestCase {
  is_vault_oracle_referenced: Bool,
  is_app_oracle_referenced: Bool,
  is_operator_signed: Bool,
  is_operation_signed: Bool,
}

fn default_withdraw_test_case() -> WithdrawTestCase {
  WithdrawTestCase {
    is_vault_oracle_referenced: True,
    is_app_oracle_referenced: True,
    is_operator_signed: True,
    is_operation_signed: False,
  }
}

fn mock_withdraw_tx(test_case: WithdrawTestCase) -> Transaction {
  let WithdrawTestCase {
    is_vault_oracle_referenced,
    is_app_oracle_referenced,
    is_operator_signed,
    is_operation_signed,
  } = test_case

  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // Vault oracle input (required for withdraw endpoint)
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
    // Signatures
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> required_signer_hash(is_operation_signed, mock_operation_key)
    |> complete()
}

fn run_withdraw(test_case: WithdrawTestCase) -> Bool {
  let tx = mock_withdraw_tx(test_case)
  vault.vault.withdraw(mock_vault_nft, Void, Void, tx)
}

// ========== Withdraw Tests ==========

test s1_withdraw_success_with_operator_signed() {
  run_withdraw(default_withdraw_test_case())
}

test s1_withdraw_success_with_operation_signed() {
  let test_case =
    WithdrawTestCase {
      ..default_withdraw_test_case(),
      is_operator_signed: False,
      is_operation_signed: True,
    }
  run_withdraw(test_case)
}

test s1_withdraw_success_with_both_signed() {
  let test_case =
    WithdrawTestCase {
      ..default_withdraw_test_case(),
      is_operator_signed: True,
      is_operation_signed: True,
    }
  run_withdraw(test_case)
}

test s1_withdraw_fail_without_vault_oracle_inputed() fail {
  let test_case =
    WithdrawTestCase {
      ..default_withdraw_test_case(),
      is_vault_oracle_referenced: False,
    }
  run_withdraw(test_case)
}

test s1_withdraw_fail_without_any_signature() {
  let test_case =
    WithdrawTestCase {
      ..default_withdraw_test_case(),
      is_operator_signed: False,
      is_operation_signed: False,
    }
  !run_withdraw(test_case)
}
