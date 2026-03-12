use cardano/address.{from_script}
use cardano/assets.{AssetName, PolicyId, from_asset_list, from_lovelace}
use cardano/transaction.{InlineDatum, Input, NoDatum}
use deposit_utils.{
  cal_lp_amount, combine_m_value, process_batched_deposit_intent_validation,
}
use mocktail.{mock_output, mock_pub_key_address, mock_utxo_ref}
use price_oracle_utils.{convert_m_value_to_usd}
use tests/utils.{
  mock_deposit_intent_script_hash, mock_lp_record_script_hash, mock_total_lp,
  mock_vault_balance,
}
use types.{DepositIntentDatum, LPRecordDatum}

pub const prices: Pairs<(PolicyId, AssetName), Int> =
  [
    Pair((#"", #""), 2),
    Pair(
      (#"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913", #"5553444d"),
      1,
    ),
  ]

pub const m_value_a =
  [
    Pair("", [Pair("", 1000000)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 1000000)],
    ),
  ]

pub const m_value_b =
  [
    Pair("", [Pair("", 2000000)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 2000000)],
    ),
  ]

pub const m_value_c =
  [
    Pair("", [Pair("", 2000000)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 1000000)],
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
    output_reference: mock_utxo_ref(99, 0),
    output: mock_output(
      mock_pub_key_address(999, None),
      from_lovelace(1000000),
      NoDatum,
      None,
    ),
  }

const input_y =
  Input {
    output_reference: mock_utxo_ref(99, 1),
    output: mock_output(
      mock_pub_key_address(999, None),
      from_lovelace(1000000),
      NoDatum,
      None,
    ),
  }

pub const intent_input_a =
  Input {
    output_reference: mock_utxo_ref(0, 0),
    output: mock_output(
      from_script(mock_deposit_intent_script_hash),
      from_asset_list(m_value_a),
      InlineDatum(deposit_intent_datum_a),
      None,
    ),
  }

pub const intent_input_b =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      from_script(mock_deposit_intent_script_hash),
      from_asset_list(m_value_b),
      InlineDatum(deposit_intent_datum_b),
      None,
    ),
  }

pub const intent_input_c =
  Input {
    output_reference: mock_utxo_ref(2, 0),
    output: mock_output(
      from_script(mock_deposit_intent_script_hash),
      from_asset_list(m_value_c),
      InlineDatum(deposit_intent_datum_c),
      None,
    ),
  }

// LP Record outputs for new depositors (no existing LP Records)
const lp_record_datum_a: Data =
  LPRecordDatum {
    address: mock_pub_key_address(0, None),
    lp: cal_lp_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
    ),
    cost: convert_m_value_to_usd(m_value_a, prices),
  }

const lp_record_datum_b: Data =
  LPRecordDatum {
    address: mock_pub_key_address(1, None),
    lp: cal_lp_amount(
      convert_m_value_to_usd(m_value_b, prices),
      mock_vault_balance,
      mock_total_lp,
    ),
    cost: convert_m_value_to_usd(m_value_b, prices),
  }

const lp_record_datum_c: Data =
  LPRecordDatum {
    address: mock_pub_key_address(2, None),
    lp: cal_lp_amount(
      convert_m_value_to_usd(m_value_c, prices),
      mock_vault_balance,
      mock_total_lp,
    ),
    cost: convert_m_value_to_usd(m_value_c, prices),
  }

pub const intent_output_a =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2000000),
    InlineDatum(lp_record_datum_a),
    None,
  )

pub const intent_output_b =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2000000),
    InlineDatum(lp_record_datum_b),
    None,
  )

pub const intent_output_c =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2000000),
    InlineDatum(lp_record_datum_c),
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

// indices: first intent found → output 1, second → output 0, third → output 2
const outputs = [intent_output_b, intent_output_a, intent_output_c]

const incorrect_outputs = [intent_output_a, intent_output_b, intent_output_c]

const indices = [1, 0, 2]

const incorrect_indices = [0, 1, 2]

const excessive_indices = [0, 1, 2, 3]

test process_batch_normal() {
  let (
    total_intent_datum_m_value,
    total_intent_datum_usd_value,
    total_lp_added,
    new_lp_records_minted,
  ) =
    process_batched_deposit_intent_validation(
      inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_record_script_hash,
    )

  (total_intent_datum_m_value == combine_m_value(
    combine_m_value(m_value_a, m_value_b),
    m_value_c,
  ))? && (total_intent_datum_usd_value == convert_m_value_to_usd(
    m_value_a,
    prices,
  ) + convert_m_value_to_usd(m_value_b, prices) + convert_m_value_to_usd(
    m_value_c,
    prices,
  ))? && (total_lp_added == cal_lp_amount(
    convert_m_value_to_usd(m_value_a, prices),
    mock_vault_balance,
    mock_total_lp,
  ) + cal_lp_amount(
    convert_m_value_to_usd(m_value_b, prices),
    mock_vault_balance,
    mock_total_lp,
  ) + cal_lp_amount(
    convert_m_value_to_usd(m_value_c, prices),
    mock_vault_balance,
    mock_total_lp,
  ))? && (new_lp_records_minted == 3)?
}

test process_batch_excessive_inputs() fail {
  let (_, _, _, _) =
    process_batched_deposit_intent_validation(
      excessive_inputs,
      outputs,
      excessive_indices,
      mock_vault_balance,
      mock_total_lp,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_record_script_hash,
    )

  True
}

test process_batch_insufficient_inputs() fail {
  let (_, _, _, _) =
    process_batched_deposit_intent_validation(
      insufficient_inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_record_script_hash,
    )

  True
}

test process_batch_incorrect_outputs() fail {
  let (_, _, _, _) =
    process_batched_deposit_intent_validation(
      inputs,
      incorrect_outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_record_script_hash,
    )

  True
}

test process_batch_incorrect_indices() fail {
  let (_, _, _, _) =
    process_batched_deposit_intent_validation(
      inputs,
      outputs,
      incorrect_indices,
      mock_vault_balance,
      mock_total_lp,
      prices,
      mock_deposit_intent_script_hash,
      mock_lp_record_script_hash,
    )

  True
}
