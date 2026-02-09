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
use types.{MintIntent, ProcessDeposit, ProcessWithdrawal}
use vault_oracle/spend as vault_oracle_spend

type ProcessIntentTestCase {
  is_vault_oracle_inputed: Bool,
  is_deposit: Bool,
  is_mint_redeemer_correct: Bool,
}

fn mock_process_intent_tx(test_case: ProcessIntentTestCase) -> Transaction {
  let ProcessIntentTestCase {
    is_vault_oracle_inputed,
    is_deposit,
    is_mint_redeemer_correct,
  } = test_case

  let mint_redeemer: Data =
    if is_mint_redeemer_correct {
      mock_burn_intent_redeemer
    } else {
      MintIntent
    }
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
    |> tx_in(True, mock_tx_hash(0), 0, input_value, mock_vault_oracle_address)
    |> tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> tx_out(True, mock_vault_oracle_address, input_value)
    |> mint(True, 1, intent_policy_id, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(intent_policy_id), mint_redeemer))
}

test s0_spend_success_process_deposit_intent() {
  let datum = mock_vault_oracle_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: True,
        is_mint_redeemer_correct: True,
      },
    )

  vault_oracle_spend.vault_oracle.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s0_spend_success_process_withdrawal_intent() {
  let datum = mock_vault_oracle_datum
  let redeemer = ProcessWithdrawal
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: False,
        is_mint_redeemer_correct: True,
      },
    )

  vault_oracle_spend.vault_oracle.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s0_spend_fail_process_intent_with_no_vault_oracle_inputed() fail {
  let datum = mock_vault_oracle_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: False,
        is_deposit: True,
        is_mint_redeemer_correct: False,
      },
    )

  vault_oracle_spend.vault_oracle.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s0_spend_fail_process_intent_with_incorrect_mint_redeemer() fail {
  let datum = mock_vault_oracle_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: True,
        is_mint_redeemer_correct: False,
      },
    )

  vault_oracle_spend.vault_oracle.spend(
    mock_vault_oracle,
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}
