use cardano/address.{from_script}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{Mint, Transaction}
use l1_withdrawal_intent/spend_and_mint as l1_withdrawal_intent
use mocktail.{
  add_redeemer, complete, mint, mock_script_hash, mock_tx_hash, mock_utxo_ref,
  mocktail_tx, tx_in, tx_in_inline_datum,
}
use tests/utils.{
  mock_l1_withdrawal_intent_script_hash, mock_user_trade_account, mock_vault_nft,
}
use types.{BurnIntent, MintIntent, WithdrawalIntentDatum}

// ========== ProcessIntent (Spend) Tests ==========
// Spec: L1WithdrawalIntent is burnt (spend just validates that mint redeemer is BurnIntent)

const mock_withdrawal_intent_datum: WithdrawalIntentDatum =
  WithdrawalIntentDatum {
    withdrawer: mock_user_trade_account,
    shares_to_redeem: 1_000_000,
  }

type ProcessIntentTestCase {
  is_mint_policy_correct: Bool,
  is_mint_redeemer_burn_intent: Bool,
}

fn mock_process_intent_tx(test_case: ProcessIntentTestCase) -> Transaction {
  let ProcessIntentTestCase {
    is_mint_policy_correct,
    is_mint_redeemer_burn_intent,
  } = test_case

  let policy_id = mock_l1_withdrawal_intent_script_hash
  let wrong_policy_id = mock_script_hash(999)

  let mint_redeemer: Data =
    if is_mint_redeemer_burn_intent {
      BurnIntent([], #"", [], [])
    } else {
      MintIntent
    }

  let mint_policy =
    if is_mint_policy_correct {
      policy_id
    } else {
      wrong_policy_id
    }

  let input_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
    |> tx_in_inline_datum(True, mock_withdrawal_intent_datum)
    |> mint(True, -1, mint_policy, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(mint_policy), mint_redeemer))
}

// Success: Spend intent with correct BurnIntent redeemer
test s3_spend_process_intent_success() {
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_mint_policy_correct: True,
        is_mint_redeemer_burn_intent: True,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.spend(
    mock_vault_nft,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// Fail: Wrong mint policy (different script)
test s3_spend_process_intent_fail_wrong_policy() fail {
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_mint_policy_correct: False,
        is_mint_redeemer_burn_intent: True,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.spend(
    mock_vault_nft,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// Fail: MintIntent redeemer instead of BurnIntent
test s3_spend_process_intent_fail_wrong_redeemer() fail {
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_mint_policy_correct: True,
        is_mint_redeemer_burn_intent: False,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.spend(
    mock_vault_nft,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}
