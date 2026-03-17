use cardano/address.{Address, from_script}
use cardano/assets.{AssetName, PolicyId, from_asset, from_lovelace}
use cardano/transaction.{InlineDatum, Input, NoDatum}
use hydra_dex/types.{Account, UserTradeAccount} as dd_types
use mocktail.{mock_output, mock_pub_key_address, mock_utxo_ref}
use tests/utils.{
  mock_l1_withdrawal_intent_script_hash, mock_l2_withdrawal_intent_script_hash,
  mock_operator_charge_percentage, mock_total_shares, mock_vault_equity,
}
use types.{MValue, WithdrawalIntentDatum}
use withdraw_utils.{
  cal_per_user_operator_fee, compute_fee_shares, convert_shares_to_usd,
}

// ========== Mock User Accounts ==========

// Inner Account types
const mock_user_inner_account_0: Account =
  Account {
    account_id: "user_0",
    master_key: mock_pub_key_address(0, None).payment_credential,
    operation_key: mock_pub_key_address(0, None).payment_credential,
  }

const mock_user_inner_account_1: Account =
  Account {
    account_id: "user_1",
    master_key: mock_pub_key_address(1, None).payment_credential,
    operation_key: mock_pub_key_address(1, None).payment_credential,
  }

const mock_user_inner_account_2: Account =
  Account {
    account_id: "user_2",
    master_key: mock_pub_key_address(2, None).payment_credential,
    operation_key: mock_pub_key_address(2, None).payment_credential,
  }

// Wrap in UserTradeAccount for intent datums
const mock_user_account_0: dd_types.UserAccount =
  UserTradeAccount {
    account: mock_user_inner_account_0,
    trading_logic: mock_l1_withdrawal_intent_script_hash,
  }

const mock_user_account_1: dd_types.UserAccount =
  UserTradeAccount {
    account: mock_user_inner_account_1,
    trading_logic: mock_l1_withdrawal_intent_script_hash,
  }

const mock_user_account_2: dd_types.UserAccount =
  UserTradeAccount {
    account: mock_user_inner_account_2,
    trading_logic: mock_l1_withdrawal_intent_script_hash,
  }

// Derive addresses from accounts for output validation
fn user_address_0() -> Address {
  Address {
    payment_credential: mock_user_inner_account_0.master_key,
    stake_credential: None,
  }
}

fn user_address_1() -> Address {
  Address {
    payment_credential: mock_user_inner_account_1.master_key,
    stake_credential: None,
  }
}

fn user_address_2() -> Address {
  Address {
    payment_credential: mock_user_inner_account_2.master_key,
    stake_credential: None,
  }
}

// ========== Constants ==========

const usdm_policy = #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913"

const usdm_name = #"5553444d"

pub const prices: Pairs<(PolicyId, AssetName), Int> =
  [Pair((#"", #""), 2), Pair((usdm_policy, usdm_name), 1)]

// ========== Shares amounts ==========
// Using values that produce meaningful withdrawal amounts

pub const shares_amount_a: Int = 1_250_000_000_000_000

pub const shares_amount_b: Int = 2_500_000_000_000_000

pub const shares_amount_c: Int = 625_000_000_000_000

// ========== Withdrawal intent datums ==========

const withdrawal_intent_datum_a: Data =
  WithdrawalIntentDatum {
    withdrawer: mock_user_account_0,
    shares_to_redeem: shares_amount_a,
  }

const withdrawal_intent_datum_b: Data =
  WithdrawalIntentDatum {
    withdrawer: mock_user_account_1,
    shares_to_redeem: shares_amount_b,
  }

const withdrawal_intent_datum_c: Data =
  WithdrawalIntentDatum {
    withdrawer: mock_user_account_2,
    shares_to_redeem: shares_amount_c,
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
      from_script(mock_l1_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(withdrawal_intent_datum_a),
      None,
    ),
  }

pub const intent_input_b =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      from_script(mock_l1_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(withdrawal_intent_datum_b),
      None,
    ),
  }

pub const intent_input_c =
  Input {
    output_reference: mock_utxo_ref(2, 0),
    output: mock_output(
      from_script(mock_l1_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(withdrawal_intent_datum_c),
      None,
    ),
  }

// ========== Input lists ==========

const inputs =
  [input_x, intent_input_a, intent_input_b, input_y, intent_input_c]

const insufficient_inputs = [input_x, intent_input_a, intent_input_b, input_y]

// ========== Indices ==========

const indices = [1, 0, 2]

const excessive_indices = [0, 1, 2, 3]

// ========== Helper functions to calculate expected values ==========

fn user_receives_a() -> Int {
  let gross =
    convert_shares_to_usd(shares_amount_a, mock_total_shares, mock_vault_equity)
  // Cost basis would come from MPF - placeholder using 50% of gross
  let cost_basis = gross / 2
  let fee =
    cal_per_user_operator_fee(
      gross,
      cost_basis,
      mock_operator_charge_percentage,
    )
  gross - fee
}

fn user_receives_b() -> Int {
  let gross =
    convert_shares_to_usd(shares_amount_b, mock_total_shares, mock_vault_equity)
  let cost_basis = gross / 2
  let fee =
    cal_per_user_operator_fee(
      gross,
      cost_basis,
      mock_operator_charge_percentage,
    )
  gross - fee
}

fn user_receives_c() -> Int {
  let gross =
    convert_shares_to_usd(shares_amount_c, mock_total_shares, mock_vault_equity)
  let cost_basis = gross / 2
  let fee =
    cal_per_user_operator_fee(
      gross,
      cost_basis,
      mock_operator_charge_percentage,
    )
  gross - fee
}

// ========== User outputs (in USDM, price=1) ==========

pub fn intent_output_a() {
  mock_output(
    user_address_0(),
    from_asset(usdm_policy, usdm_name, user_receives_a()),
    NoDatum,
    None,
  )
}

pub fn intent_output_b() {
  mock_output(
    user_address_1(),
    from_asset(usdm_policy, usdm_name, user_receives_b()),
    NoDatum,
    None,
  )
}

pub fn intent_output_c() {
  mock_output(
    user_address_2(),
    from_asset(usdm_policy, usdm_name, user_receives_c()),
    NoDatum,
    None,
  )
}

// indices = [1, 0, 2] → intent_a→output[1], intent_b→output[0], intent_c→output[2]
fn outputs() {
  [intent_output_b(), intent_output_a(), intent_output_c()]
}

fn incorrect_outputs() {
  [intent_output_a(), intent_output_b(), intent_output_c()]
}

// ========== L2 Intent inputs (using L2 script hash) ==========
// In L2, indices are only used for COUNTING (values ignored).
// Transfer amounts are matched in order with intent UTxOs.

const l2_withdrawal_intent_datum_a: Data =
  WithdrawalIntentDatum {
    withdrawer: mock_user_account_0,
    shares_to_redeem: shares_amount_a,
  }

const l2_withdrawal_intent_datum_b: Data =
  WithdrawalIntentDatum {
    withdrawer: mock_user_account_1,
    shares_to_redeem: shares_amount_b,
  }

const l2_withdrawal_intent_datum_c: Data =
  WithdrawalIntentDatum {
    withdrawer: mock_user_account_2,
    shares_to_redeem: shares_amount_c,
  }

pub const l2_intent_input_a =
  Input {
    output_reference: mock_utxo_ref(10, 0),
    output: mock_output(
      from_script(mock_l2_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(l2_withdrawal_intent_datum_a),
      None,
    ),
  }

pub const l2_intent_input_b =
  Input {
    output_reference: mock_utxo_ref(11, 0),
    output: mock_output(
      from_script(mock_l2_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(l2_withdrawal_intent_datum_b),
      None,
    ),
  }

pub const l2_intent_input_c =
  Input {
    output_reference: mock_utxo_ref(12, 0),
    output: mock_output(
      from_script(mock_l2_withdrawal_intent_script_hash),
      from_lovelace(2000000),
      InlineDatum(l2_withdrawal_intent_datum_c),
      None,
    ),
  }

// L2 input list
const l2_inputs =
  [input_x, l2_intent_input_a, l2_intent_input_b, input_y, l2_intent_input_c]

// L2 indices — only used for counting, actual values ignored
// We have 3 intents, so 3 indices (values don't matter for L2)
const l2_indices = [0, 0, 0]

// L2 transfer amounts as MValue (in USDM, price=1 means USD value = amount)
// These must match user_receives_a, user_receives_b, user_receives_c in order
fn l2_transfer_amount_a() -> MValue {
  [Pair(usdm_policy, [Pair(usdm_name, user_receives_a())])]
}

fn l2_transfer_amount_b() -> MValue {
  [Pair(usdm_policy, [Pair(usdm_name, user_receives_b())])]
}

fn l2_transfer_amount_c() -> MValue {
  [Pair(usdm_policy, [Pair(usdm_name, user_receives_c())])]
}

// Transfer amounts in order matching intent processing order
// Intents are processed: a, b, c (in input list order, skipping non-intent)
fn l2_transfer_amounts() -> List<MValue> {
  [l2_transfer_amount_a(), l2_transfer_amount_b(), l2_transfer_amount_c()]
}

// Incorrect transfer amounts (wrong order)
fn l2_incorrect_transfer_amounts() -> List<MValue> {
  [l2_transfer_amount_b(), l2_transfer_amount_a(), l2_transfer_amount_c()]
}

// ========== Expected totals ==========

const expected_total_shares =
  shares_amount_a + shares_amount_b + shares_amount_c

const expected_total_user_receives =
  user_receives_a() + user_receives_b() + user_receives_c()
// ========== Tests ==========
// TODO: Add merkle proofs and complete tests once merkle data is prepared

// test process_batch_normal() {
//   let (
//     total_shares_amount,
//     total_user_receives,
//     total_fee_shares,
//     total_cost_removed,
//     final_merkle_root,
//   ) =
//     process_batched_withdrawal_intent_validation(
//       inputs,
//       outputs,
//       indices,
//       mpf_actions,  // TODO: provide merkle proof actions
//       mock_vault_equity,
//       mock_total_shares,
//       mock_operator_charge_percentage,
//       prices,
//       mock_l1_withdrawal_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//
//   (total_shares_amount == expected_total_shares)? &&
//   (total_user_receives == expected_total_user_receives)?
// }

// test process_batch_insufficient_inputs() fail {
//   // TODO: Add merkle data
// }

// test process_batch_excessive_indices() fail {
//   // TODO: Add merkle data
// }

// test process_batch_incorrect_outputs() fail {
//   // TODO: Add merkle data
// }

// ========== L2 Tests ==========
// L2 uses TransferIntent mechanism instead of direct outputs.
// indices are only for counting (values ignored), transfer_amounts matched in order.
// TODO: Add merkle proofs and complete tests once merkle data is prepared

// test l2_process_batch_normal() {
//   let (
//     total_shares_amount,
//     total_user_receives,
//     total_fee_shares,
//     total_cost_removed,
//     final_merkle_root,
//   ) =
//     process_batched_l2_withdrawal_intent_validation(
//       l2_inputs,
//       l2_indices,  // Only used for counting, values ignored
//       mpf_actions,  // TODO: provide merkle proof actions
//       l2_transfer_amounts(),
//       mock_vault_equity,
//       mock_total_shares,
//       mock_operator_charge_percentage,
//       prices,
//       mock_l2_withdrawal_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//
//   (total_shares_amount == expected_total_shares)? &&
//   (total_user_receives == expected_total_user_receives)?
// }

// test l2_process_batch_mismatched_transfer_amounts() fail {
//   // Transfer amounts don't match calculated user_receives
//   let (_, _, _, _, _) =
//     process_batched_l2_withdrawal_intent_validation(
//       l2_inputs,
//       l2_indices,
//       mpf_actions,  // TODO: provide merkle proof actions
//       l2_incorrect_transfer_amounts(),  // Wrong order causes mismatch
//       mock_vault_equity,
//       mock_total_shares,
//       mock_operator_charge_percentage,
//       prices,
//       mock_l2_withdrawal_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//   True
// }

// test l2_process_batch_extra_transfer_amounts() fail {
//   // More transfer amounts than withdrawal intents
//   let extra_transfers =
//     [l2_transfer_amount_a(), l2_transfer_amount_b(), l2_transfer_amount_c(), l2_transfer_amount_a()]
//   let (_, _, _, _, _) =
//     process_batched_l2_withdrawal_intent_validation(
//       l2_inputs,
//       l2_indices,
//       mpf_actions,  // TODO: provide merkle proof actions
//       extra_transfers,
//       mock_vault_equity,
//       mock_total_shares,
//       mock_operator_charge_percentage,
//       prices,
//       mock_l2_withdrawal_intent_script_hash,
//       initial_merkle_root,  // TODO: provide initial root
//     )
//   True
// }
