use cardano/address.{from_script}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{Transaction}
use l2_withdrawal_intent/spend_and_mint as l2_withdrawal_intent
use mocktail.{
  complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, tx_in,
  tx_in_inline_datum,
}
use tests/utils.{
  mock_l2_withdrawal_intent_script_hash, mock_user_trade_account, mock_vault_nft,
}
use types.{L2WithdrawalIntentDatum}

// ========== ProcessIntent (Spend) Tests ==========
// Spec: L2WithdrawalIntent spend is allowed when intent token is being burnt

const mock_l2_withdrawal_intent_datum: L2WithdrawalIntentDatum =
  L2WithdrawalIntentDatum {
    vault_oracle_nft: mock_vault_nft,
    withdrawer: mock_user_trade_account,
    shares_to_redeem: 1_000_000,
  }

type ProcessIntentTestCase {
  is_intent_token_burnt: Bool,
  is_burn_amount_correct: Bool,
}

fn mock_process_intent_tx(test_case: ProcessIntentTestCase) -> Transaction {
  let ProcessIntentTestCase { is_intent_token_burnt, is_burn_amount_correct } =
    test_case

  let policy_id = mock_l2_withdrawal_intent_script_hash

  // L2 intent input only has intent token + min ADA
  let input_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

  // Burn amount: -1 for correct, 1 for minting instead
  let burn_amount =
    if is_intent_token_burnt {
      if is_burn_amount_correct {
        -1
      } else {
        -2
      }
    } else {
      1
    }

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
    |> tx_in_inline_datum(True, mock_l2_withdrawal_intent_datum)
    |> mint(True, burn_amount, policy_id, "")
    |> complete()
}

// Success: Spend intent when token is burnt
test s5_spend_process_intent_success() {
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_intent_token_burnt: True,
        is_burn_amount_correct: True,
      },
    )

  l2_withdrawal_intent.l2_withdrawal_intent.spend(
    mock_vault_nft,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// Fail: Token minted instead of burnt
test s5_spend_process_intent_fail_token_minted() {
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_intent_token_burnt: False,
        is_burn_amount_correct: True,
      },
    )

  !l2_withdrawal_intent.l2_withdrawal_intent.spend(
    mock_vault_nft,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}
