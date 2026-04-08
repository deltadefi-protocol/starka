use cardano/address.{Script, from_script}
use cardano/assets.{from_asset, from_lovelace}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mock_tx_hash, mocktail_tx, ref_tx_in, ref_tx_in_inline_datum,
  required_signer_hash, script_withdrawal, tx_in, tx_out,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_operation_key, mock_vault_nft, mock_vault_oracle_datum,
  mock_vault_script_hash, mock_vault_stake_rotation_script_hash,
}
use vault/stake_rotation as vault_stake_rotation

// ==================== Withdraw ====================

type WithdrawTestCase {
  is_operation_key_signed: Bool,
  is_value_unlocked_correct: Bool,
}

fn mock_withdraw_tx(test_case: WithdrawTestCase) -> Transaction {
  let WithdrawTestCase { is_operation_key_signed, is_value_unlocked_correct } =
    test_case

  let vault_address = from_script(mock_vault_script_hash)
  let vault_oracle_address = from_script(mock_vault_nft)

  mocktail_tx()
    |> ref_tx_in(
        True,
        mock_tx_hash(0),
        0,
        from_asset(mock_vault_nft, "", 1),
        vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> ref_tx_in(
        True,
        mock_tx_hash(2),
        0,
        from_asset(mock_app_oracle, "", 1),
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(True, mock_app_oracle_datum)
    |> script_withdrawal(True, mock_vault_stake_rotation_script_hash, 0)
    |> tx_in(True, mock_tx_hash(1), 0, from_lovelace(10_000_000), vault_address)
    |> tx_in(True, mock_tx_hash(1), 1, from_lovelace(10_000_000), vault_address)
    |> tx_in(True, mock_tx_hash(1), 2, from_lovelace(10_000_000), vault_address)
    |> tx_out(True, vault_address, from_lovelace(10_000_000))
    |> tx_out(True, vault_address, from_lovelace(10_000_000))
    |> tx_out(
        is_value_unlocked_correct,
        vault_address,
        from_lovelace(10_000_000),
      )
    |> required_signer_hash(is_operation_key_signed, mock_operation_key)
    |> complete()
}

fn run_withdraw(test_case: WithdrawTestCase) -> Bool {
  let tx = mock_withdraw_tx(test_case)

  vault_stake_rotation.app_vault_stake_rotation.withdraw(
    mock_vault_nft,
    Void,
    Script(mock_vault_stake_rotation_script_hash),
    tx,
  )
}

test s1_stake_rotation_withdraw_success_stake_rotation() {
  run_withdraw(
    WithdrawTestCase {
      is_operation_key_signed: True,
      is_value_unlocked_correct: True,
    },
  )
}

test s1_stake_rotation_withdraw_fail_unauthorized_stake_rotation() {
  !run_withdraw(
    WithdrawTestCase {
      is_operation_key_signed: False,
      is_value_unlocked_correct: True,
    },
  )
}

test s1_stake_rotation_withdraw_fail_incorrect_value_after_stake_rotation() {
  !run_withdraw(
    WithdrawTestCase {
      is_operation_key_signed: True,
      is_value_unlocked_correct: False,
    },
  )
}
