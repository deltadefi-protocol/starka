use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, tx_in,
  tx_in_inline_datum, tx_out,
}
use oracle/spend as vault_oracle_spend
use tests/utils.{
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
}
use types.{ProcessDeposit, ProcessWithdrawal, VaultOracleDatum}

type ProcessIntentTestCase {
  is_vault_oracle_inputed: Bool,
  is_oracle_nft_burnt: Bool,
}

fn mock_process_intent_tx(test_case: ProcessIntentTestCase) -> Transaction {
  let ProcessIntentTestCase { is_vault_oracle_inputed, is_oracle_nft_burnt } =
    test_case

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
    |> mint(is_oracle_nft_burnt, -1, mock_vault_oracle, "")
    |> complete()
}

test s0_spend_success() {
  let datum = VaultOracleDatum { ..mock_vault_oracle_datum, is_active: False }
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_oracle_nft_burnt: True,
      },
    )

  vault_oracle_spend.vault_oracle.spend(
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s0_spend_failed_without_vault_oracle() {
  let datum = VaultOracleDatum { ..mock_vault_oracle_datum, is_active: False }
  let redeemer = ProcessWithdrawal
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: False,
        is_oracle_nft_burnt: True,
      },
    )

  !vault_oracle_spend.vault_oracle.spend(
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s0_spend_fail_without_oracle_nft_burnt() {
  let datum = VaultOracleDatum { ..mock_vault_oracle_datum, is_active: False }
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_oracle_nft_burnt: False,
      },
    )

  !vault_oracle_spend.vault_oracle.spend(
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s0_spend_fail_with_active_oracle() {
  let datum = mock_vault_oracle_datum
  let redeemer = ProcessDeposit
  let tx =
    mock_process_intent_tx(
      ProcessIntentTestCase {
        is_vault_oracle_inputed: True,
        is_oracle_nft_burnt: True,
      },
    )

  !vault_oracle_spend.vault_oracle.spend(
    Some(datum),
    redeemer,
    mock_utxo_ref(0, 0),
    tx,
  )
}
