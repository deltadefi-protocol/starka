use cardano/address.{from_script, from_verification_key}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Input, NoDatum, Transaction}
use mocktail.{
  add_input, add_output, complete, mint, mock_output, mock_tx_hash,
  mock_utxo_ref, mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_input_oracle_datum,
  mock_lp_token, mock_message, mock_operator_fee, mock_operator_key,
  mock_pluggable_logic, mock_signatures, mock_total_lp, mock_vault_balance,
  mock_vault_cost, mock_vault_oracle, mock_vault_oracle_address,
  mock_vault_oracle_datum, mock_vault_script_hash,
  mock_withdrawal_intent_script_hash,
}
use tests/withdraw_utils/process_batch.{
  intent_input_a, intent_output_a, lp_amount_a,
}
use types.{BurnIntent, VaultOracleDatum}
use withdraw_utils.{convert_lp_to_usd}
use withdrawal_intent/spend_and_mint as withdrawal_intent_spend_and_mint

const vault_input_a =
  Input {
    output_reference: mock_utxo_ref(10, 0),
    output: mock_output(
      from_script(mock_vault_script_hash),
      from_asset(
        #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
        #"5553444d",
        convert_lp_to_usd(
          lp_amount_a,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ) * 2,
      ),
      NoDatum,
      None,
    ),
  }

const indices =
  [
    2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
  ]

const utxo_ref = mock_utxo_ref(0, 0)

// current max = 18
// MAX [mem: 14,000,100, cpu: 10,000,000,000]
// PASS [mem: 13,492,908, cpu: 4,592,431,371]
fn mock_burn_withdrawal_intent_tx() -> Transaction {
  let vault_oracle_input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let vault_oracle_output_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let app_oracle_ref_input_value =
    from_asset(mock_app_oracle, "", 1)
      |> add("", "", 2_000_000)

  //todo
  let total_intent_datum_lp_amount =
    lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a + lp_amount_a

  //todo
  let total_intent_datum_lp_usd_value =
    convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    ) + convert_lp_to_usd(
      lp_amount_a,
      mock_total_lp,
      mock_vault_balance,
      mock_operator_fee,
    )
  let vault_output_datum =
    VaultOracleDatum {
      ..mock_vault_oracle_datum,
      total_lp: mock_total_lp - total_intent_datum_lp_amount,
      hwm_lp_value: mock_vault_balance - mock_operator_fee - total_intent_datum_lp_usd_value,
      vault_cost: mock_vault_cost - total_intent_datum_lp_usd_value,
    }

  //todo
  let intent_burn_amount = 32

  let operator_output_value =
    from_asset(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      #"5553444d",
      mock_operator_fee,
    )

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
    |> mint(
        True,
        -total_intent_datum_lp_amount,
        mock_lp_token,
        mock_pluggable_logic,
      )
    |> mint(True, -intent_burn_amount, mock_withdrawal_intent_script_hash, "")
    |> tx_out(
        True,
        from_verification_key(mock_operator_key),
        operator_output_value,
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
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
    |> add_input(True, vault_input_a)
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

test withdrawal_batch_limit_test() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx = mock_burn_withdrawal_intent_tx()

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}
