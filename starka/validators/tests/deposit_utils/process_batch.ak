use cardano/address.{from_script}
use cardano/assets.{from_asset, from_asset_list}
use cardano/transaction.{InlineDatum, Input, NoDatum}
use deposit_utils.{
  cal_lp_token_amount, combine_m_value, convert_m_value_to_usdm,
  process_batched_deposit_intent_validation,
}
use mocktail.{mock_output, mock_pub_key_address, mock_utxo_ref}
use tests/utils.{
  mock_deposit_intent_script_hash, mock_lp_token, mock_pluggable_logic,
}
use types.{DepositIntentDatum}

const mock_total_lp = 1000000000000

const mock_vault_balance = 1000000

const mock_operator_fee = 0

const prices: Pairs<ByteArray, Int> =
  [
    Pair(#"", 2),
    Pair(#"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c9135553444d", 1),
  ]

const m_value_a =
  [
    Pair("", [Pair("", 100)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 100)],
    ),
  ]

const m_value_b =
  [
    Pair("", [Pair("", 200)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 200)],
    ),
  ]

const m_value_c =
  [
    Pair("", [Pair("", 200)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 10)],
    ),
  ]

const deposit_intent_datum_a: Data =
  DepositIntentDatum {
    lp_address: mock_pub_key_address(0, None),
    amount: m_value_a,
  }

const deposit_intent_datum_b: Data =
  DepositIntentDatum {
    lp_address: mock_pub_key_address(1, None),
    amount: m_value_b,
  }

const deposit_intent_datum_c: Data =
  DepositIntentDatum {
    lp_address: mock_pub_key_address(2, None),
    amount: m_value_c,
  }

const input_x =
  Input {
    output_reference: mock_utxo_ref(0, 0),
    output: mock_output(
      mock_pub_key_address(999, None),
      from_asset_list(m_value_a),
      InlineDatum(deposit_intent_datum_a),
      None,
    ),
  }

const input_y =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      mock_pub_key_address(999, None),
      from_asset_list(m_value_c),
      InlineDatum(deposit_intent_datum_b),
      None,
    ),
  }

const intent_input_a =
  Input {
    output_reference: mock_utxo_ref(0, 0),
    output: mock_output(
      from_script(mock_deposit_intent_script_hash),
      from_asset_list(m_value_a),
      InlineDatum(deposit_intent_datum_a),
      None,
    ),
  }

const intent_input_b =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      from_script(mock_deposit_intent_script_hash),
      from_asset_list(m_value_b),
      InlineDatum(deposit_intent_datum_b),
      None,
    ),
  }

const intent_input_c =
  Input {
    output_reference: mock_utxo_ref(2, 0),
    output: mock_output(
      from_script(mock_deposit_intent_script_hash),
      from_asset_list(m_value_b),
      InlineDatum(deposit_intent_datum_c),
      None,
    ),
  }

const intent_output_a =
  mock_output(
    mock_pub_key_address(0, None),
    from_asset(
      mock_lp_token,
      mock_pluggable_logic,
      cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_a, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

const intent_output_b =
  mock_output(
    mock_pub_key_address(1, None),
    from_asset(
      mock_lp_token,
      mock_pluggable_logic,
      cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_b, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

const intent_output_c =
  mock_output(
    mock_pub_key_address(2, None),
    from_asset(
      mock_lp_token,
      mock_pluggable_logic,
      cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_c, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

const inputs =
  [input_x, intent_input_a, intent_input_b, input_y, intent_input_c]

const excessive_inputs =
  [
    input_x, intent_input_a, intent_input_b, input_y, intent_input_c,
    intent_input_c,
  ]

const insufficient_inputs = [input_x, intent_input_a, intent_input_b, input_y]

const outputs = [intent_output_b, intent_output_a, intent_output_c]

const incorrect_outputs = [intent_output_a, intent_output_b]

const indices = [1, 0, 2]

const incorrect_indices = [0, 1, 2]

const excessive_indices = [0, 1, 2, 3]

test process_batch_normal() {
  let (
    total_intent_datum_m_value,
    total_intent_datum_usdm_value,
    total_lp_token_sent,
  ) =
    process_batched_deposit_intent_validation(
      inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_token,
      mock_pluggable_logic,
    )

  total_intent_datum_m_value == combine_m_value(
    combine_m_value(m_value_a, m_value_b),
    m_value_c,
  ) && total_intent_datum_usdm_value == convert_m_value_to_usdm(
    m_value_a,
    prices,
  ) + convert_m_value_to_usdm(m_value_b, prices) + convert_m_value_to_usdm(
    m_value_c,
    prices,
  ) && total_lp_token_sent == cal_lp_token_amount(
    total_intent_datum_usdm_value,
    mock_vault_balance,
    mock_total_lp,
    mock_operator_fee,
  )
}

test process_batch_excessive_inputs() fail {
  let (
    total_intent_datum_m_value,
    total_intent_datum_usdm_value,
    total_lp_token_sent,
  ) =
    process_batched_deposit_intent_validation(
      excessive_inputs,
      outputs,
      excessive_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_token,
      mock_pluggable_logic,
    )

  total_intent_datum_m_value == combine_m_value(
    combine_m_value(m_value_a, m_value_b),
    m_value_c,
  ) && total_intent_datum_usdm_value == convert_m_value_to_usdm(
    m_value_a,
    prices,
  ) + convert_m_value_to_usdm(m_value_b, prices) + convert_m_value_to_usdm(
    m_value_c,
    prices,
  ) && total_lp_token_sent == cal_lp_token_amount(
    total_intent_datum_usdm_value,
    mock_vault_balance,
    mock_total_lp,
    mock_operator_fee,
  )
}

test process_batch_insufficient_inputs() fail {
  let (
    total_intent_datum_m_value,
    total_intent_datum_usdm_value,
    total_lp_token_sent,
  ) =
    process_batched_deposit_intent_validation(
      insufficient_inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_token,
      mock_pluggable_logic,
    )

  total_intent_datum_m_value == combine_m_value(
    combine_m_value(m_value_a, m_value_b),
    m_value_c,
  ) && total_intent_datum_usdm_value == convert_m_value_to_usdm(
    m_value_a,
    prices,
  ) + convert_m_value_to_usdm(m_value_b, prices) + convert_m_value_to_usdm(
    m_value_c,
    prices,
  ) && total_lp_token_sent == cal_lp_token_amount(
    total_intent_datum_usdm_value,
    mock_vault_balance,
    mock_total_lp,
    mock_operator_fee,
  )
}

test process_batch_incorrect_outputs() fail {
  let (
    total_intent_datum_m_value,
    total_intent_datum_usdm_value,
    total_lp_token_sent,
  ) =
    process_batched_deposit_intent_validation(
      inputs,
      incorrect_outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_token,
      mock_pluggable_logic,
    )

  total_intent_datum_m_value == combine_m_value(
    combine_m_value(m_value_a, m_value_b),
    m_value_c,
  ) && total_intent_datum_usdm_value == convert_m_value_to_usdm(
    m_value_a,
    prices,
  ) + convert_m_value_to_usdm(m_value_b, prices) + convert_m_value_to_usdm(
    m_value_c,
    prices,
  ) && total_lp_token_sent == cal_lp_token_amount(
    total_intent_datum_usdm_value,
    mock_vault_balance,
    mock_total_lp,
    mock_operator_fee,
  )
}

test process_batch_incorrect_indices() fail {
  let (
    total_intent_datum_m_value,
    total_intent_datum_usdm_value,
    total_lp_token_sent,
  ) =
    process_batched_deposit_intent_validation(
      inputs,
      outputs,
      incorrect_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_token,
      mock_pluggable_logic,
    )

  total_intent_datum_m_value == combine_m_value(
    combine_m_value(m_value_a, m_value_b),
    m_value_c,
  ) && total_intent_datum_usdm_value == convert_m_value_to_usdm(
    m_value_a,
    prices,
  ) + convert_m_value_to_usdm(m_value_b, prices) + convert_m_value_to_usdm(
    m_value_c,
    prices,
  ) && total_lp_token_sent == cal_lp_token_amount(
    total_intent_datum_usdm_value,
    mock_vault_balance,
    mock_total_lp,
    mock_operator_fee,
  )
}
