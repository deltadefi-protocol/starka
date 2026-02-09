use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use mocktail.{
  add_extra_signatory, complete, mock_tx_hash, mocktail_tx, tx_in,
  tx_in_inline_datum, tx_out,
}
use tests/utils.{
  mock_operator_key, mock_vault_oracle, mock_vault_oracle_address,
  mock_vault_oracle_datum,
}
use vault/spend_and_withdraw as vault_spend_and_withdraw

type ProcessWithdrawalTestCase {
  is_vault_oracle_inputed: Bool,
  is_operator_signed: Bool,
}

fn mock_process_withdrawal_tx(
  test_case: ProcessWithdrawalTestCase,
) -> Transaction {
  let ProcessWithdrawalTestCase { is_vault_oracle_inputed, is_operator_signed } =
    test_case

  let input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    |> tx_in(
        is_vault_oracle_inputed,
        mock_tx_hash(1),
        0,
        input_value,
        mock_vault_oracle_address,
      )
    |> tx_in_inline_datum(is_vault_oracle_inputed, mock_vault_oracle_datum)
    |> tx_out(is_vault_oracle_inputed, mock_vault_oracle_address, input_value)
    |> complete()
    |> add_extra_signatory(is_operator_signed, mock_operator_key)
}

test s1_withdraw_success_process_withdrawal() {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: True,
        is_operator_signed: True,
      },
    )

  vault_spend_and_withdraw.vault.withdraw(mock_vault_oracle, None, None, tx)
}

test s1_withdraw_fail_process_withdrawal_with_no_vault_oracle_inputed() fail {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: False,
        is_operator_signed: True,
      },
    )

  vault_spend_and_withdraw.vault.withdraw(mock_vault_oracle, None, None, tx)
}

test s1_withdraw_fail_process_withdrawal_with_no_operator_signed() {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: True,
        is_operator_signed: False,
      },
    )

  !vault_spend_and_withdraw.vault.withdraw(mock_vault_oracle, None, None, tx)
}
