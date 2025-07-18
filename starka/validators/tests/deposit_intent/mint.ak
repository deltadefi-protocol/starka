use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_asset_list, from_lovelace}
use cardano/transaction.{Mint, Transaction}
use deposit_intent/spend_and_mint as deposit_intent_spend_and_mint
use mocktail.{
  complete, mint, mock_policy_id, mocktail_tx, tx_in, tx_in_inline_datum, tx_out,
  tx_out_inline_datum,
}
use tests/utils.{
  mock_burn_intent_redeemer, mock_deposit_intent_datum,
  mock_deposit_intent_script_hash, mock_deposit_m_value, mock_vault_oracle,
  mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_withdrawal_intent_script_hash, to_mvalue,
}
use types.{MValue, MintIntent}

type MintDepositIntentTestCase {
  is_deposit_intent_minted: Bool,
  is_token_output_clean: Bool,
  is_value_deposited_correctly: Bool,
}

fn mock_mint_deposit_intent_tx(
  test_case: MintDepositIntentTestCase,
) -> Transaction {
  let MintDepositIntentTestCase {
    is_deposit_intent_minted,
    is_token_output_clean,
    is_value_deposited_correctly,
  } = test_case

  let deposit_value: MValue = mock_deposit_m_value

  let incorrect_deposit_value =
    from_asset("A", "abc", 1)
      |> add("C", "def", 10)
      |> to_mvalue()

  let output_datum = mock_deposit_intent_datum
  mocktail_tx()
    |> mint(is_deposit_intent_minted, 1, mock_deposit_intent_script_hash, "")
    |> tx_out(
        is_value_deposited_correctly,
        from_script(mock_deposit_intent_script_hash),
        from_asset_list(deposit_value)
          |> add(mock_deposit_intent_script_hash, "", 1),
      )
    |> tx_out(
        !is_value_deposited_correctly,
        from_script(mock_deposit_intent_script_hash),
        from_asset_list(incorrect_deposit_value),
      )
    |> tx_out_inline_datum(True, output_datum)
    |> tx_out(
        !is_token_output_clean,
        from_script(mock_deposit_intent_script_hash),
        from_asset_list(deposit_value)
          |> add(mock_deposit_intent_script_hash, "", 1)
          |> add(mock_policy_id(999), "", 1),
      )
    |> tx_out_inline_datum(!is_token_output_clean, output_datum)
    |> complete()
}

test s4_mint_success_mint_deposit_intent() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: True,
        is_token_output_clean: True,
        is_value_deposited_correctly: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_mint_deposit_intent_with_no_intent_minted() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: False,
        is_token_output_clean: True,
        is_value_deposited_correctly: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_mint_deposit_intent_with_intent_output_not_clean() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: True,
        is_token_output_clean: False,
        is_value_deposited_correctly: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_mint_deposit_intent_with_value_deposited_incorrect() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: True,
        is_token_output_clean: True,
        is_value_deposited_correctly: False,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}
