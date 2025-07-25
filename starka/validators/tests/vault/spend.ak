use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, tx_in,
  tx_in_inline_datum, tx_out,
}
use tests/utils.{
  mock_burn_intent_redeemer, mock_deposit_intent_script_hash, mock_vault_oracle,
  mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_withdrawal_intent_script_hash,
}
use types.{MintIntent, WithdrawFund}
use vault/spend_and_withdraw as vault_spend_and_withdraw

type ProcessWithdrawalTestCase {
  is_vault_oracle_inputed: Bool,
  is_mint_policy_correct: Bool,
  is_mint_redeemer_correct: Bool,
}

fn mock_process_withdrawal_tx(
  test_case: ProcessWithdrawalTestCase,
) -> Transaction {
  let ProcessWithdrawalTestCase {
    is_vault_oracle_inputed,
    is_mint_policy_correct,
    is_mint_redeemer_correct,
  } = test_case

  let mint_redeemer: Data =
    if is_mint_redeemer_correct {
      mock_burn_intent_redeemer
    } else {
      MintIntent
    }
  let intent_policy_id =
    if is_mint_policy_correct {
      mock_withdrawal_intent_script_hash
    } else {
      mock_deposit_intent_script_hash
    }
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
    |> mint(True, 1, intent_policy_id, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(intent_policy_id), mint_redeemer))
}

test s1_spend_success_process_withdrawal() {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: True,
        is_mint_policy_correct: True,
        is_mint_redeemer_correct: True,
      },
    )

  vault_spend_and_withdraw.vault.spend(
    mock_vault_oracle,
    None,
    WithdrawFund,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s1_spend_fail_process_withdrawal_with_no_vault_oracle_inputed() fail {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: False,
        is_mint_policy_correct: True,
        is_mint_redeemer_correct: True,
      },
    )

  vault_spend_and_withdraw.vault.spend(
    mock_vault_oracle,
    None,
    WithdrawFund,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s1_spend_fail_process_withdrawal_with_incorrect_mint_policy() fail {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: True,
        is_mint_policy_correct: False,
        is_mint_redeemer_correct: True,
      },
    )

  vault_spend_and_withdraw.vault.spend(
    mock_vault_oracle,
    None,
    WithdrawFund,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s1_spend_fail_process_withdrawal_with_incorrect_mint_redeemer() fail {
  let tx =
    mock_process_withdrawal_tx(
      ProcessWithdrawalTestCase {
        is_vault_oracle_inputed: True,
        is_mint_policy_correct: True,
        is_mint_redeemer_correct: False,
      },
    )

  vault_spend_and_withdraw.vault.spend(
    mock_vault_oracle,
    None,
    WithdrawFund,
    mock_utxo_ref(0, 0),
    tx,
  )
}
