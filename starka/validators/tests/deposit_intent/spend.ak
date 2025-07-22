use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use deposit_intent/spend_and_mint as deposit_intent_spend_and_mint
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, tx_in,
  tx_in_inline_datum,
}
use tests/utils.{
  mock_burn_intent_redeemer, mock_deposit_intent_datum,
  mock_deposit_intent_script_hash, mock_vault_oracle,
  mock_withdrawal_intent_script_hash,
}
use types.{MintIntent}

type ProcessdepositTestCase {
  is_mint_policy_correct: Bool,
  is_mint_redeemer_correct: Bool,
}

fn mock_process_deposit_tx(test_case: ProcessdepositTestCase) -> Transaction {
  let ProcessdepositTestCase {
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
      mock_deposit_intent_script_hash
    } else {
      mock_withdrawal_intent_script_hash
    }
  let input_value =
    from_asset(mock_deposit_intent_script_hash, "", 1)
      |> add("", "", 2_000_000)

  mocktail_tx()
    |> tx_in(
        True,
        mock_tx_hash(0),
        0,
        input_value,
        from_script(mock_deposit_intent_script_hash),
      )
    |> tx_in_inline_datum(True, mock_deposit_intent_datum)
    |> mint(True, 1, intent_policy_id, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(intent_policy_id), mint_redeemer))
}

test s2_spend_success_process_deposit() {
  let tx =
    mock_process_deposit_tx(
      ProcessdepositTestCase {
        is_mint_policy_correct: True,
        is_mint_redeemer_correct: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s2_spend_fail_process_deposit_with_incorrect_mint_policy() fail {
  let tx =
    mock_process_deposit_tx(
      ProcessdepositTestCase {
        is_mint_policy_correct: False,
        is_mint_redeemer_correct: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s2_spend_fail_process_deposit_with_incorrect_mint_redeemer() fail {
  let tx =
    mock_process_deposit_tx(
      ProcessdepositTestCase {
        is_mint_policy_correct: True,
        is_mint_redeemer_correct: False,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}
