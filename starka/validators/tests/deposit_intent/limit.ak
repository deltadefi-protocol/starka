use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use deposit_intent/spend_and_mint as deposit_intent_spend_and_mint
use deposit_utils.{cal_lp_token_amount, combine_m_value, convert_m_value_to_usd}
use mocktail.{
  add_input, add_output, complete, mint, mock_tx_hash, mock_utxo_ref,
  mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, tx_in, tx_in_inline_datum,
  tx_out, tx_out_inline_datum,
}
use tests/deposit_utils/process_batch.{
  intent_input_a, intent_output_a, m_value_a, prices,
}
use tests/utils.{
  mock_app_deposit_request_address, mock_app_deposit_request_token,
  mock_app_oracle, mock_app_oracle_address, mock_deposit_intent_script_hash,
  mock_input_oracle_datum, mock_lp_decimal, mock_lp_token, mock_message,
  mock_operator_fee, mock_signatures, mock_total_lp, mock_vault_balance,
  mock_vault_cost, mock_vault_oracle, mock_vault_oracle_address,
  mock_vault_oracle_datum,
}
use types.{BurnIntent, VaultOracleDatum}

//todo
const indices = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]

const utxo_ref = mock_utxo_ref(0, 0)

// current max = 18
// MAX [mem: 14,000,100, cpu: 10,000,000,000]
// PASS [mem: 13,460,150, cpu: 4,218,762,850]
fn mock_burn_deposit_intent_tx() -> Transaction {
  let vault_oracle_input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let vault_oracle_output_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let app_oracle_ref_input_value =
    from_asset(mock_app_oracle, "", 1)
      |> add("", "", 2_000_000)

  //todo
  let total_intent_datum_usd_value =
    convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    ) + convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_a,
      prices,
    )
  //todo
  let total_lp_token_minted =
    cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    ) + cal_lp_token_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
    )

  let vault_output_datum =
    VaultOracleDatum {
      ..mock_vault_oracle_datum,
      total_lp: mock_total_lp + total_lp_token_minted,
      hwm_lp_value: mock_vault_balance - mock_operator_fee + total_intent_datum_usd_value,
      vault_cost: mock_vault_cost + total_intent_datum_usd_value,
    }

  //todo
  let intent_burn_amount = 18

  //todo
  let app_deposit_request_output_value =
    from_asset_list(
      combine_m_value(
        combine_m_value(
          combine_m_value(
            combine_m_value(m_value_a, m_value_a),
            combine_m_value(m_value_a, m_value_a),
          ),
          combine_m_value(
            combine_m_value(m_value_a, m_value_a),
            combine_m_value(m_value_a, m_value_a),
          ),
        ),
        combine_m_value(
          combine_m_value(
            combine_m_value(m_value_a, m_value_a),
            combine_m_value(m_value_a, m_value_a),
          ),
          combine_m_value(
            combine_m_value(m_value_a, m_value_a),
            combine_m_value(
              combine_m_value(m_value_a, m_value_a),
              combine_m_value(m_value_a, m_value_a),
            ),
          ),
        ),
      ),
    )
      |> add(mock_app_deposit_request_token, "", 1)

  mocktail_tx()
    |> tx_in(
        True,
        utxo_ref.transaction_id,
        utxo_ref.output_index,
        vault_oracle_input_value,
        mock_vault_oracle_address,
      )
    |> tx_in_inline_datum(True, mock_vault_oracle_datum)
    |> ref_tx_in(
        True,
        mock_tx_hash(0),
        1,
        app_oracle_ref_input_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(True, mock_input_oracle_datum)
    |> tx_out(True, mock_vault_oracle_address, vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_output_datum)
    |> mint(True, total_lp_token_minted, mock_lp_token, "")
    |> mint(True, -intent_burn_amount, mock_deposit_intent_script_hash, "")
    |> tx_out(
        True,
        mock_app_deposit_request_address,
        app_deposit_request_output_value,
      )
    |> complete()
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_a)
}

test deposit_batch_limit_test() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx = mock_burn_deposit_intent_tx()

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    mock_lp_decimal,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}
