use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, tx_out,
}
use tests/utils.{
  mock_deposit_intent_script_hash, mock_vault_oracle, mock_vault_oracle_address,
  mock_vault_oracle_datum, mock_vault_state_datum,
  mock_withdrawal_intent_script_hash,
}
use types.{ProcessDeposit, ProcessWithdrawal}
use vault_state/spend_mint as vault_state

type ProcessIntentTestCase {
  is_vault_oracle_inputed: Bool,
  is_deposit: Bool,
  is_intent_burnt: Bool,
}

fn mock_process_intent_tx(test_case: ProcessIntentTestCase) -> Transaction {
  let ProcessIntentTestCase {
    is_vault_oracle_inputed,
    is_deposit,
    is_intent_burnt,
  } = test_case

  let intent_policy_id =
    if is_deposit {
      mock_deposit_intent_script_hash
    } else {
      mock_withdrawal_intent_script_hash
    }
  let input_value =
    if is_vault_oracle_inputed {
      from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)
    } else {
      from_asset("", "", 1) |> add("", "", 1)
    }

  mocktail_tx()
    |> ref_tx_in(
        True,
        mock_tx_hash(0),
        0,
        input_value,
        mock_vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> tx_out(True, mock_vault_oracle_address, input_value)
    |> mint(is_intent_burnt, -1, intent_policy_id, "")
    |> complete()
}

test s1_spend_success_process_deposit_intent() {
  let datum = mock_vault_state_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: True,
        is_intent_burnt: True,
      },
    )

  vault_state.vault_state.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s1_spend_success_process_withdrawal_intent() {
  let datum = mock_vault_state_datum
  let redeemer = ProcessWithdrawal
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: False,
        is_intent_burnt: True,
      },
    )

  vault_state.vault_state.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s1_spend_fail_process_intent_with_no_vault_oracle_inputed() fail {
  let datum = mock_vault_state_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: False,
        is_deposit: True,
        is_intent_burnt: False,
      },
    )

  vault_state.vault_state.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s1_spend_fail_process_intent_without_intent_burnt() {
  let datum = mock_vault_state_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: True,
        is_intent_burnt: False,
      },
    )

  !vault_state.vault_state.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}
