use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use lp_token/mint as lp_token_mint
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mocktail_tx, tx_in,
  tx_in_inline_datum, tx_out,
}
use tests/utils.{
  mock_burn_intent_redeemer, mock_deposit_intent_script_hash, mock_lp_token,
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_withdrawal_intent_script_hash,
}
use types.{MintIntent, ProcessDeposit, ProcessWithdrawal}

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

test s4_mint_success_process_deposit_intent() {
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: True,
        is_mint_redeemer_correct: True,
      },
    )

  lp_token_mint.lp_token.mint(mock_vault_oracle, redeemer, mock_lp_token, tx)
}

test s4_mint_success_process_withdrawal_intent() {
  let redeemer = ProcessWithdrawal
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: False,
        is_mint_redeemer_correct: True,
      },
    )

  lp_token_mint.lp_token.mint(mock_vault_oracle, redeemer, mock_lp_token, tx)
}

test s4_mint_fail_process_intent_with_no_vault_oracle_inputed() fail {
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: False,
        is_deposit: True,
        is_mint_redeemer_correct: False,
      },
    )

  lp_token_mint.lp_token.mint(mock_vault_oracle, redeemer, mock_lp_token, tx)
}

test s4_mint_fail_process_intent_with_incorrect_mint_redeemer() fail {
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_deposit: True,
        is_mint_redeemer_correct: False,
      },
    )

  lp_token_mint.lp_token.mint(mock_vault_oracle, redeemer, mock_lp_token, tx)
}
