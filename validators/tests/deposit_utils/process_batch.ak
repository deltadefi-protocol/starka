use cardano/address.{from_script}
use cardano/assets.{AssetName, PolicyId, from_asset_list, from_lovelace}
use cardano/transaction.{InlineDatum, Input, NoDatum}
use deposit_utils.{cal_shares_amount, combine_m_value}
use mocktail.{mock_output, mock_pub_key_address, mock_utxo_ref}
use price_oracle_utils.{convert_m_value_to_usd}
use tests/utils.{
  mock_l1_deposit_intent_script_hash, mock_l2_deposit_intent_script_hash,
  mock_total_shares, mock_vault_equity,
}
use types.{DepositIntentDatum, MValue}

// ========== Prices ==========

pub const prices: Pairs<(PolicyId, AssetName), Int> =
  [
    Pair((#"", #""), 2),
    Pair(
      (#"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913", #"5553444d"),
      1,
    ),
  ]

// ========== MValue constants ==========

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

// ========== Deposit intent datums ==========

const deposit_intent_datum_a: Data =
  DepositIntentDatum {
    depositor: mock_pub_key_address(0, None),
    deposit_amount: m_value_a,
  }

const deposit_intent_datum_b: Data =
  DepositIntentDatum {
    depositor: mock_pub_key_address(1, None),
    deposit_amount: m_value_b,
  }

const deposit_intent_datum_c: Data =
  DepositIntentDatum {
    depositor: mock_pub_key_address(2, None),
    deposit_amount: m_value_c,
  }

// ========== Non-intent inputs ==========

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

// ========== Intent inputs ==========

pub const intent_input_a =
  Input {
    output_reference: mock_utxo_ref(0, 0),
    output: mock_output(
      from_script(mock_l1_deposit_intent_script_hash),
      from_asset_list(m_value_a),
      InlineDatum(deposit_intent_datum_a),
      None,
    ),
  }

pub const intent_input_b =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      from_script(mock_l1_deposit_intent_script_hash),
      from_asset_list(m_value_b),
      InlineDatum(deposit_intent_datum_b),
      None,
    ),
  }

pub const intent_input_c =
  Input {
    output_reference: mock_utxo_ref(2, 0),
    output: mock_output(
      from_script(mock_l1_deposit_intent_script_hash),
      from_asset_list(m_value_c),
      InlineDatum(deposit_intent_datum_c),
      None,
    ),
  }

// ========== Input lists ==========

const inputs =
  [input_x, intent_input_a, intent_input_b, input_y, intent_input_c]

const excessive_inputs =
  [
    input_x, intent_input_a, intent_input_b, input_y, intent_input_c,
    intent_input_c,
  ]

const insufficient_inputs = [input_x, intent_input_a, intent_input_b, input_y]

// ========== Indices ==========
// NOTE: The actual index values are NOT used in process_batched_deposit_intent_validation.
// Only the LENGTH of indices matters - it acts as a counter to ensure the correct number
// of deposit intent UTxOs are processed. The index values are discarded with `_output_index`.
// See deposit_utils.ak line 120: `[_output_index, ..rest_of_indices]`
//
// This means [1, 0, 2], [0, 1, 2], [99, 99, 99] would all work the same as long as length = 3.
// The indices were originally meant to map to output indices but are now only used for counting.

const indices = [1, 0, 2]

// NOTE: This would actually work the same as `indices` since only length matters
const incorrect_indices = [0, 1, 2]

const excessive_indices = [0, 1, 2, 3]

// ========== Expected values ==========

// m_value_a USD = 1000000 * 2 + 1000000 * 1 = 3000000
// m_value_b USD = 2000000 * 2 + 2000000 * 1 = 6000000
// m_value_c USD = 2000000 * 2 + 1000000 * 1 = 5000000
// Total USD = 14000000

const expected_total_m_value =
  combine_m_value(combine_m_value(m_value_a, m_value_b), m_value_c)

const expected_total_usd =
  convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
    m_value_b,
    prices,
  ) + convert_m_value_to_usd(m_value_c, prices)

const expected_total_shares =
  cal_shares_amount(
    convert_m_value_to_usd(m_value_a, prices),
    mock_vault_equity,
    mock_total_shares,
  ) + cal_shares_amount(
    convert_m_value_to_usd(m_value_b, prices),
    mock_vault_equity,
    mock_total_shares,
  ) + cal_shares_amount(
    convert_m_value_to_usd(m_value_c, prices),
    mock_vault_equity,
    mock_total_shares,
  )
// ========== Tests ==========
// TODO: Add merkle proofs and complete tests once merkle data is prepared

// test process_batch_normal() {
//   let (
//     total_intent_datum_m_value,
//     total_intent_datum_usd_value,
//     total_shares_added,
//     final_merkle_root,
//   ) =
//     process_batched_deposit_intent_validation(
//       inputs,
//       indices,
//       mpf_actions,  // TODO: provide merkle proof actions
//       mock_vault_equity,
//       mock_total_shares,
//       prices,
//       mock_l1_deposit_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//
//   (total_intent_datum_m_value == expected_total_m_value)? &&
//   (total_intent_datum_usd_value == expected_total_usd)? &&
//   (total_shares_added == expected_total_shares)?
// }

// test process_batch_excessive_inputs() fail {
//   // TODO: Add merkle data
// }

// test process_batch_insufficient_inputs() fail {
//   // TODO: Add merkle data
// }

// ========== L2 Intent inputs (using L2 script hash) ==========
// In L2, indices are only used for COUNTING (values ignored).
// Transfer amounts are matched in order with intent UTxOs.
// Validation compares USD values (not MValue directly).

const l2_deposit_intent_datum_a: Data =
  DepositIntentDatum {
    depositor: mock_pub_key_address(0, None),
    deposit_amount: m_value_a,
  }

const l2_deposit_intent_datum_b: Data =
  DepositIntentDatum {
    depositor: mock_pub_key_address(1, None),
    deposit_amount: m_value_b,
  }

const l2_deposit_intent_datum_c: Data =
  DepositIntentDatum {
    depositor: mock_pub_key_address(2, None),
    deposit_amount: m_value_c,
  }

pub const l2_intent_input_a =
  Input {
    output_reference: mock_utxo_ref(10, 0),
    output: mock_output(
      from_script(mock_l2_deposit_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(l2_deposit_intent_datum_a),
      None,
    ),
  }

pub const l2_intent_input_b =
  Input {
    output_reference: mock_utxo_ref(11, 0),
    output: mock_output(
      from_script(mock_l2_deposit_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(l2_deposit_intent_datum_b),
      None,
    ),
  }

pub const l2_intent_input_c =
  Input {
    output_reference: mock_utxo_ref(12, 0),
    output: mock_output(
      from_script(mock_l2_deposit_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(l2_deposit_intent_datum_c),
      None,
    ),
  }

// L2 input list
const l2_inputs =
  [input_x, l2_intent_input_a, l2_intent_input_b, input_y, l2_intent_input_c]

// L2 indices — only used for counting, actual values ignored
const l2_indices = [0, 0, 0]

// L2 transfer amounts as MValue — must match deposit_amount in USD value
// Intents are processed in order: a, b, c
fn l2_transfer_amounts() -> List<MValue> {
  [m_value_a, m_value_b, m_value_c]
}

// Incorrect transfer amounts (wrong order causes USD value mismatch)
fn l2_incorrect_transfer_amounts() -> List<MValue> {
  [m_value_b, m_value_a, m_value_c]
}

// ========== L2 Tests ==========
// L2 uses TransferIntent mechanism instead of storing value in intent UTxO.
// indices are only for counting (values ignored), transfer_amounts matched in order.
// Validation compares USD values of deposit_amount and transfer_amount.
// TODO: Add merkle proofs and complete tests once merkle data is prepared

// test l2_process_batch_normal() {
//   let (total_usd_value, total_shares_added, final_merkle_root) =
//     process_batched_l2_deposit_intent_validation(
//       l2_inputs,
//       l2_indices,  // Only used for counting, values ignored
//       mpf_actions,  // TODO: provide merkle proof actions
//       l2_transfer_amounts(),
//       mock_vault_equity,
//       mock_total_shares,
//       prices,
//       mock_l2_deposit_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//
//   (total_usd_value == expected_total_usd)? &&
//   (total_shares_added == expected_total_shares)?
// }

// test l2_process_batch_mismatched_transfer_amounts() fail {
//   // Transfer amounts don't match deposit_amount in USD value
//   let (_, _, _) =
//     process_batched_l2_deposit_intent_validation(
//       l2_inputs,
//       l2_indices,
//       mpf_actions,  // TODO: provide merkle proof actions
//       l2_incorrect_transfer_amounts(),  // Wrong order causes USD mismatch
//       mock_vault_equity,
//       mock_total_shares,
//       prices,
//       mock_l2_deposit_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//   True
// }

// test l2_process_batch_extra_transfer_amounts() fail {
//   // More transfer amounts than deposit intents
//   let extra_transfers = [m_value_a, m_value_b, m_value_c, m_value_a]
//   let (_, _, _) =
//     process_batched_l2_deposit_intent_validation(
//       l2_inputs,
//       l2_indices,
//       mpf_actions,  // TODO: provide merkle proof actions
//       extra_transfers,
//       mock_vault_equity,
//       mock_total_shares,
//       prices,
//       mock_l2_deposit_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//   True
// }
