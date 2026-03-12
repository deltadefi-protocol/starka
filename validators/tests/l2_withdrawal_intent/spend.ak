use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint}
use l2_withdrawal_intent/spend_and_mint as l2_withdrawal_intent
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, tx_in,
  tx_in_inline_datum,
}
use tests/utils.{
  mock_l2_withdrawal_intent_script_hash, mock_vault_nft,
  mock_withdrawal_intent_datum,
}
use types.{BurnIntent}

test test_spend_success() {
  let policy_id = mock_l2_withdrawal_intent_script_hash
  let burn_redeemer: Data = BurnIntent([0], "", [], [])
  let input_value =
    from_asset(policy_id, "", 1) |> add("", "", 2_000_000)
  let tx =
    mocktail_tx()
      |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
      |> tx_in_inline_datum(True, mock_withdrawal_intent_datum)
      |> mint(True, -1, policy_id, "")
      |> complete()
      |> add_redeemer(True, Pair(Mint(policy_id), burn_redeemer))

  l2_withdrawal_intent.l2_withdrawal_intent.spend(
    mock_vault_nft,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}
