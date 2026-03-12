use cardano/address.{from_script}
use cardano/assets.{AssetName, PolicyId, from_asset, from_lovelace}
use cardano/transaction.{InlineDatum, Input, NoDatum}
use mocktail.{mock_output, mock_pub_key_address, mock_utxo_ref}
use tests/utils.{
  mock_lp_record_script_hash, mock_operator_charge_percentage, mock_total_lp,
  mock_vault_balance, mock_withdrawal_intent_script_hash,
}
use types.{LPRecordDatum, WithdrawalIntentDatum}
use withdraw_utils.{
  cal_per_user_operator_fee, convert_lp_to_usd,
  process_batched_withdrawal_intent_validation,
}

const usdm_policy = #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913"

const usdm_name = #"5553444d"

pub const prices: Pairs<(PolicyId, AssetName), Int> =
  [
    Pair((#"", #""), 2),
    Pair((usdm_policy, usdm_name), 1),
  ]

// LP amounts large enough to produce meaningful withdrawal values
// withdrawal_value = lp_amount * 2_400_000_000 / 3_000_000_000_000_000
pub const lp_amount_a: Int = 1_250_000_000_000

pub const lp_amount_b: Int = 2_500_000_000_000

pub const lp_amount_c: Int = 625_000_000_000

// User A: partial withdrawal (has 2x what they withdraw)
const lp_record_a_lp = 2_500_000_000_000

const lp_record_a_cost = 1_500_000

// User B: total withdrawal (withdraws all LP)
const lp_record_b_lp = 2_500_000_000_000

const lp_record_b_cost = 2_000_000

// User C: partial withdrawal (has 2x what they withdraw)
const lp_record_c_lp = 1_250_000_000_000

const lp_record_c_cost = 400_000

// Withdrawal intent datums
const withdrawal_intent_datum_a: Data =
  WithdrawalIntentDatum {
    lp_address: mock_pub_key_address(0, None),
    amount: lp_amount_a,
  }

const withdrawal_intent_datum_b: Data =
  WithdrawalIntentDatum {
    lp_address: mock_pub_key_address(1, None),
    amount: lp_amount_b,
  }

const withdrawal_intent_datum_c: Data =
  WithdrawalIntentDatum {
    lp_address: mock_pub_key_address(2, None),
    amount: lp_amount_c,
  }

// LP Record datums for inputs
const lp_record_datum_a_input: Data =
  LPRecordDatum {
    address: mock_pub_key_address(0, None),
    lp: lp_record_a_lp,
    cost: lp_record_a_cost,
  }

const lp_record_datum_b_input: Data =
  LPRecordDatum {
    address: mock_pub_key_address(1, None),
    lp: lp_record_b_lp,
    cost: lp_record_b_cost,
  }

const lp_record_datum_c_input: Data =
  LPRecordDatum {
    address: mock_pub_key_address(2, None),
    lp: lp_record_c_lp,
    cost: lp_record_c_cost,
  }

// Non-intent inputs
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

// Withdrawal intent inputs
pub const intent_input_a =
  Input {
    output_reference: mock_utxo_ref(0, 0),
    output: mock_output(
      from_script(mock_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(withdrawal_intent_datum_a),
      None,
    ),
  }

pub const intent_input_b =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      from_script(mock_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(withdrawal_intent_datum_b),
      None,
    ),
  }

pub const intent_input_c =
  Input {
    output_reference: mock_utxo_ref(2, 0),
    output: mock_output(
      from_script(mock_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(withdrawal_intent_datum_c),
      None,
    ),
  }

// LP Record inputs
const lp_record_input_a =
  Input {
    output_reference: mock_utxo_ref(50, 0),
    output: mock_output(
      from_script(mock_lp_record_script_hash),
      from_lovelace(2000000),
      InlineDatum(lp_record_datum_a_input),
      None,
    ),
  }

const lp_record_input_b =
  Input {
    output_reference: mock_utxo_ref(51, 0),
    output: mock_output(
      from_script(mock_lp_record_script_hash),
      from_lovelace(2000000),
      InlineDatum(lp_record_datum_b_input),
      None,
    ),
  }

const lp_record_input_c =
  Input {
    output_reference: mock_utxo_ref(52, 0),
    output: mock_output(
      from_script(mock_lp_record_script_hash),
      from_lovelace(2000000),
      InlineDatum(lp_record_datum_c_input),
      None,
    ),
  }

// User asset outputs: value in USDM (price=1) matching user_receives
fn user_receives_a() -> Int {
  let wv = convert_lp_to_usd(lp_amount_a, mock_total_lp, mock_vault_balance)
  let cb = lp_record_a_cost * lp_amount_a / lp_record_a_lp
  let fee =
    cal_per_user_operator_fee(wv, cb, mock_operator_charge_percentage)
  wv - fee
}

fn user_receives_b() -> Int {
  let wv = convert_lp_to_usd(lp_amount_b, mock_total_lp, mock_vault_balance)
  let cb = lp_record_b_cost * lp_amount_b / lp_record_b_lp
  let fee =
    cal_per_user_operator_fee(wv, cb, mock_operator_charge_percentage)
  wv - fee
}

fn user_receives_c() -> Int {
  let wv = convert_lp_to_usd(lp_amount_c, mock_total_lp, mock_vault_balance)
  let cb = lp_record_c_cost * lp_amount_c / lp_record_c_lp
  let fee =
    cal_per_user_operator_fee(wv, cb, mock_operator_charge_percentage)
  wv - fee
}

pub const intent_output_a =
  mock_output(
    mock_pub_key_address(0, None),
    from_asset(usdm_policy, usdm_name, user_receives_a()),
    NoDatum,
    None,
  )

pub const intent_output_b =
  mock_output(
    mock_pub_key_address(1, None),
    from_asset(usdm_policy, usdm_name, user_receives_b()),
    NoDatum,
    None,
  )

pub const intent_output_c =
  mock_output(
    mock_pub_key_address(2, None),
    from_asset(usdm_policy, usdm_name, user_receives_c()),
    NoDatum,
    None,
  )

// LP Record outputs for partial withdrawals
const lp_record_datum_a_output: Data =
  LPRecordDatum {
    address: mock_pub_key_address(0, None),
    lp: lp_record_a_lp - lp_amount_a,
    cost: lp_record_a_cost - lp_record_a_cost * lp_amount_a / lp_record_a_lp,
  }

const lp_record_datum_c_output: Data =
  LPRecordDatum {
    address: mock_pub_key_address(2, None),
    lp: lp_record_c_lp - lp_amount_c,
    cost: lp_record_c_cost - lp_record_c_cost * lp_amount_c / lp_record_c_lp,
  }

const lp_record_output_a =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2000000),
    InlineDatum(lp_record_datum_a_output),
    None,
  )

const lp_record_output_c =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2000000),
    InlineDatum(lp_record_datum_c_output),
    None,
  )

// Inputs: non-intent, intent_a, intent_b, non-intent, intent_c, lp_records
const inputs =
  [
    input_x, intent_input_a, intent_input_b, input_y, intent_input_c,
    lp_record_input_a, lp_record_input_b, lp_record_input_c,
  ]

// Outputs: [user_b, user_a, user_c, lp_record_a, lp_record_c]
// indices = [1, 0, 2] maps intent A→1, B→0, C→2
// lp_record_output_indices = [3, 4] maps A→3, C→4 (B is total, no LP Record output)
const outputs =
  [
    intent_output_b, intent_output_a, intent_output_c, lp_record_output_a,
    lp_record_output_c,
  ]

const indices = [1, 0, 2]

const lp_record_indices = [3, 4]

test process_batch_normal() {
  let (
    total_lp_withdrawn,
    total_user_receives,
    total_fee_retained,
    total_lp_records_burned,
    total_cost_removed,
  ) =
    process_batched_withdrawal_intent_validation(
      inputs,
      outputs,
      indices,
      lp_record_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_charge_percentage,
      prices,
      mock_withdrawal_intent_script_hash,
      mock_lp_record_script_hash,
    )

  (total_lp_withdrawn == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_user_receives == user_receives_a() + user_receives_b() + user_receives_c())? && (total_fee_retained == convert_lp_to_usd(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
  ) - user_receives_a() + convert_lp_to_usd(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
  ) - user_receives_b() + convert_lp_to_usd(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
  ) - user_receives_c())? && (total_lp_records_burned == 1)? && (total_cost_removed == lp_record_a_cost * lp_amount_a / lp_record_a_lp + lp_record_b_cost * lp_amount_b / lp_record_b_lp + lp_record_c_cost * lp_amount_c / lp_record_c_lp)?
}

test process_batch_insufficient_inputs() fail {
  let insufficient_inputs =
    [
      input_x, intent_input_a, intent_input_b, input_y,
      lp_record_input_a, lp_record_input_b,
    ]
  let (_, _, _, _, _) =
    process_batched_withdrawal_intent_validation(
      insufficient_inputs,
      outputs,
      indices,
      lp_record_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_charge_percentage,
      prices,
      mock_withdrawal_intent_script_hash,
      mock_lp_record_script_hash,
    )
  True
}

test process_batch_excessive_indices() fail {
  let excessive_indices = [0, 1, 2, 3]
  let (_, _, _, _, _) =
    process_batched_withdrawal_intent_validation(
      inputs,
      outputs,
      excessive_indices,
      lp_record_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_charge_percentage,
      prices,
      mock_withdrawal_intent_script_hash,
      mock_lp_record_script_hash,
    )
  True
}

test process_batch_incorrect_outputs() fail {
  let incorrect_outputs =
    [
      intent_output_a, intent_output_b, intent_output_c, lp_record_output_a,
      lp_record_output_c,
    ]
  let (_, _, _, _, _) =
    process_batched_withdrawal_intent_validation(
      inputs,
      incorrect_outputs,
      indices,
      lp_record_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_charge_percentage,
      prices,
      mock_withdrawal_intent_script_hash,
      mock_lp_record_script_hash,
    )
  True
}
