use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use deposit_utils.{cal_lp_token_amount,
  combine_m_value, convert_m_value_to_usdm}
use mocktail.{
  add_input, add_output, complete, mint, mock_policy_id, mock_tx_hash,
  mock_utxo_ref, mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/deposit_utils/process_batch.{
  intent_input_a, intent_input_b, intent_input_c, intent_output_a,
  intent_output_b, intent_output_c, m_value_a, m_value_b, m_value_c, prices,
}
use tests/utils.{
  mock_app_deposit_request_address, mock_app_deposit_request_token,
  mock_app_oracle, mock_app_oracle_address, mock_deposit_intent_datum,
  mock_deposit_intent_script_hash, mock_deposit_m_value, mock_input_oracle_datum,
  mock_lp_token, mock_message, mock_operator_fee, mock_pluggable_logic,
  mock_signatures, mock_total_lp, mock_vault_balance, mock_vault_cost,
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_withdrawal_intent_datum, mock_withdrawal_intent_script_hash, to_mvalue,
}
use types.{BurnIntent, MValue, MintIntent, VaultOracleDatum}
use withdrawal_intent/spend_and_mint as withdrawal_intent_spend_and_mint

type MintWithdrawalIntentTestCase {
  is_vault_oracle_inputed: Bool,
  is_withdrawal_intent_minted: Bool,
  is_token_output_clean: Bool,
  is_lp_token_locked: Bool,
}

fn mock_mint_withdrawal_intent_tx(
  test_case: MintWithdrawalIntentTestCase,
) -> Transaction {
  let MintWithdrawalIntentTestCase {
    is_vault_oracle_inputed,
    is_withdrawal_intent_minted,
    is_token_output_clean,
    is_lp_token_locked,
  } = test_case
  let vault_oracle_input_value =
    if is_vault_oracle_inputed {
      from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)
    } else {
      from_asset("", "", 1) |> add("", "", 1)
    }
  let withdrawal_value: Int =
    if is_lp_token_locked {
      1000000
    } else {
      1000010
    }

  let output_datum = mock_withdrawal_intent_datum
  mocktail_tx()
    |> ref_tx_in(
        True,
        mock_tx_hash(0),
        1,
        vault_oracle_input_value,
        mock_vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> mint(
        is_withdrawal_intent_minted,
        1,
        mock_withdrawal_intent_script_hash,
        "",
      )
    |> tx_out(
        is_token_output_clean,
        from_script(mock_withdrawal_intent_script_hash),
        from_asset(mock_lp_token, mock_pluggable_logic, withdrawal_value)
          |> add(mock_withdrawal_intent_script_hash, "", 1),
      )
    |> tx_out(
        !is_token_output_clean,
        from_script(mock_withdrawal_intent_script_hash),
        from_asset(mock_lp_token, mock_pluggable_logic, withdrawal_value)
          |> add(mock_withdrawal_intent_script_hash, "", 1)
          |> add(mock_policy_id(999), "", 1),
      )
    |> tx_out_inline_datum(True, output_datum)
    |> complete()
}

test s3_mint_success_mint_withdrawal_intent() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_vault_oracle_inputed: True,
        is_withdrawal_intent_minted: True,
        is_token_output_clean: True,
        is_lp_token_locked: True,
      },
    )

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_mint_withdrawal_intent_with_no_vault_oracle_inputed() fail {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_vault_oracle_inputed: False,
        is_withdrawal_intent_minted: True,
        is_token_output_clean: True,
        is_lp_token_locked: True,
      },
    )

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_mint_withdrawal_intent_with_no_intent_minted() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_vault_oracle_inputed: True,
        is_withdrawal_intent_minted: False,
        is_token_output_clean: True,
        is_lp_token_locked: True,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_mint_withdrawal_intent_with_intent_output_not_clean() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_vault_oracle_inputed: True,
        is_withdrawal_intent_minted: True,
        is_token_output_clean: False,
        is_lp_token_locked: True,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_mint_withdrawal_intent_with_value_deposited_incorrect() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_vault_oracle_inputed: True,
        is_withdrawal_intent_minted: True,
        is_token_output_clean: True,
        is_lp_token_locked: False,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}
