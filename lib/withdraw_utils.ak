use aiken/cbor
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input, Output}
use cocktail.{input_inline_datum}
use price_oracle_utils.{convert_m_value_to_usd}
use types.{
  MValue, SharesDelete, SharesInsert, SharesMPFAction, SharesRecordEntry,
  SharesUpdate, WithdrawalIntentDatum,
}

pub type Scott5<a, b, c, d, e, result> =
  fn(a, b, c, d, e) -> result

pub fn list_foldl5(
  self: List<x>,
  zero_a: a,
  zero_b: b,
  zero_c: c,
  zero_d: d,
  zero_e: e,
  with: fn(x, a, b, c, d, e, Scott5<a, b, c, d, e, result>) -> result,
  return: Scott5<a, b, c, d, e, result>,
) -> result {
  when self is {
    [] -> return(zero_a, zero_b, zero_c, zero_d, zero_e)
    [x, ..xs] -> {
      let
        acc_a,
        acc_b,
        acc_c,
        acc_d,
        acc_e,
      <- with(x, zero_a, zero_b, zero_c, zero_d, zero_e)
      list_foldl5(xs, acc_a, acc_b, acc_c, acc_d, acc_e, with, return)
    }
  }
}

pub fn convert_shares_to_usd(
  shares_amount: Int,
  total_shares: Int,
  vault_equity: Int,
) -> Int {
  shares_amount * vault_equity / total_shares
}

// Round UP: ceil(a * b / c) = (a * b + c - 1) / c
fn ceil_div(numerator: Int, denominator: Int) -> Int {
  ( numerator + denominator - 1 ) / denominator
}

pub fn cal_per_user_operator_fee(
  withdrawal_value: Int,
  cost_basis: Int,
  operator_charge_percentage: Int,
) -> Int {
  let profit = withdrawal_value - cost_basis
  if profit <= 0 {
    0
  } else {
    // Round UP — fee never underpaid
    ceil_div(profit * operator_charge_percentage, 100)
  }
}

pub fn compute_fee_shares(fee: Int, total_shares: Int, vault_equity: Int) -> Int {
  // Round UP — protects operator
  ceil_div(fee * total_shares, vault_equity)
}

pub fn check_output_value_equal_to_shares_usd_value(
  output_value: Value,
  shares_usd_value: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
) -> Bool {
  assets.reduce(
    output_value,
    0,
    fn(policy_id, asset_name, amount, acc) {
      expect Some(price) = prices |> pairs.get_first((policy_id, asset_name))

      acc + amount * price
    },
  ) == shares_usd_value
}

// Process batched withdrawal intents with MPF merkle root transitions.
// Returns (total_shares_amount, total_user_receives, total_fee_shares, total_cost_removed, final_merkle_root)
pub fn process_batched_withdrawal_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: List<Int>,
  mpf_actions: List<SharesMPFAction>,
  vault_equity: Int,
  total_shares: Int,
  operator_charge_percentage: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  withdrawal_intent_script_hash: ScriptHash,
  initial_merkle_root: ByteArray,
) -> (Int, Int, Int, Int, ByteArray) {
  // Accumulate: (state_triple, total_shares, total_user_receives, total_fee_shares, total_cost_removed)
  let
    processed_state,
    total_intent_datum_shares_amount,
    total_user_receives,
    total_fee_shares,
    total_cost_removed,
  <-
    list_foldl5(
      inputs,
      (indices, mpf_actions, initial_merkle_root),
      0,
      0,
      0,
      0,
      fn(
        input,
        remaining_state,
        cal_intent_datum_shares_amount,
        cal_user_receives,
        cal_fee_shares,
        cal_cost_removed,
        return,
      ) {
        let (remaining_indices, remaining_actions, current_root) =
          remaining_state
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == withdrawal_intent_script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [output_index, ..rest_of_indices] -> {
                  expect Some(out_utxo) = outputs |> list.at(output_index)
                  expect input_datum: WithdrawalIntentDatum =
                    input_inline_datum(input)

                  let WithdrawalIntentDatum { withdrawer, shares_to_redeem } =
                    input_datum

                  let new_cal_intent_datum_shares_amount =
                    cal_intent_datum_shares_amount + shares_to_redeem

                  // Calculate gross value
                  let gross_value =
                    convert_shares_to_usd(
                      shares_to_redeem,
                      total_shares,
                      vault_equity,
                    )

                  // Apply MPF action and compute cost_basis
                  expect [action, ..rest_actions] = remaining_actions
                  let mpf_key = cbor.serialise(withdrawer)

                  let (cost_basis, new_root) =
                    when action is {
                      SharesDelete { proof, old_value } -> {
                        // Total withdrawal
                        expect Some(old_data) = cbor.deserialise(old_value)
                        expect old_entry: SharesRecordEntry = old_data
                        expect shares_to_redeem == old_entry.shares
                        let cb = old_entry.total_deposited
                        let trie = mpf.from_root(current_root)
                        let new_trie =
                          mpf.delete(trie, mpf_key, old_value, proof)
                        (cb, mpf.root(new_trie))
                      }
                      SharesUpdate { from, to, to_proof } -> {
                        // Partial withdrawal
                        expect Some(from_data) = cbor.deserialise(from)
                        expect old_entry: SharesRecordEntry = from_data
                        expect old_entry.shares >= shares_to_redeem
                        let cb =
                          old_entry.total_deposited * shares_to_redeem / old_entry.shares
                        let expected_entry =
                          SharesRecordEntry {
                            shares: old_entry.shares - shares_to_redeem,
                            total_deposited: old_entry.total_deposited - cb,
                          }
                        let expected_value = cbor.serialise(expected_entry)
                        expect to == expected_value
                        let trie = mpf.from_root(current_root)
                        let new_trie =
                          mpf.update(trie, mpf_key, to_proof, from, to)
                        (cb, mpf.root(new_trie))
                      }
                      _ -> fail @"Invalid MPF action for withdrawal"
                    }

                  // Fee calculation (round UP)
                  let fee =
                    cal_per_user_operator_fee(
                      gross_value,
                      cost_basis,
                      operator_charge_percentage,
                    )
                  let fee_shares =
                    compute_fee_shares(fee, total_shares, vault_equity)
                  let user_receives = gross_value - fee

                  let new_cal_user_receives = cal_user_receives + user_receives
                  let new_cal_fee_shares = cal_fee_shares + fee_shares

                  // Check output value and address
                  let output_check =
                    check_output_value_equal_to_shares_usd_value(
                      out_utxo.value,
                      user_receives,
                      prices,
                    ) && out_utxo.address == withdrawer

                  if output_check {
                    return(
                      (rest_of_indices, rest_actions, new_root),
                      new_cal_intent_datum_shares_amount,
                      new_cal_user_receives,
                      new_cal_fee_shares,
                      cal_cost_removed + cost_basis,
                    )
                  } else {
                    fail @"Withdrawal intent output incorrect"
                  }
                }
              }
            } else {
              return(
                remaining_state,
                cal_intent_datum_shares_amount,
                cal_user_receives,
                cal_fee_shares,
                cal_cost_removed,
              )
            }
          _ ->
            return(
              remaining_state,
              cal_intent_datum_shares_amount,
              cal_user_receives,
              cal_fee_shares,
              cal_cost_removed,
            )
        }
      },
    )
  let (remaining_indices, _, final_root) = processed_state
  when remaining_indices is {
    [] ->
      (
        total_intent_datum_shares_amount,
        total_user_receives,
        total_fee_shares,
        total_cost_removed,
        final_root,
      )
    _ -> fail @"Batch withdrawal intent UTxOs not fully processed"
  }
}

// L2-specific batch processing that validates each withdrawal payout
// matches the corresponding TransferIntent amount (in USD value).
// Returns (total_shares_amount, total_user_receives, total_fee_shares, total_cost_removed, final_merkle_root)
//
// Note on `indices` parameter:
// In L2, indices are only used for COUNTING intent UTxOs (the actual index values
// are ignored). Unlike L1 where indices point to specific outputs, L2 uses
// TransferIntent mechanism where transfer_amounts are matched in order with
// intent UTxOs as they're processed.
pub fn process_batched_l2_withdrawal_intent_validation(
  inputs: List<Input>,
  indices: List<Int>,
  mpf_actions: List<SharesMPFAction>,
  transfer_amounts: List<MValue>,
  vault_equity: Int,
  total_shares: Int,
  operator_charge_percentage: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  withdrawal_intent_script_hash: ScriptHash,
  initial_merkle_root: ByteArray,
) -> (Int, Int, Int, Int, ByteArray) {
  // Accumulate: (state_tuple, total_shares, total_user_receives, total_fee_shares, total_cost_removed)
  // state_tuple = (indices, mpf_actions, transfer_amounts, merkle_root)
  let
    processed_state,
    total_intent_datum_shares_amount,
    total_user_receives,
    total_fee_shares,
    total_cost_removed,
  <-
    list_foldl5(
      inputs,
      (indices, mpf_actions, transfer_amounts, initial_merkle_root),
      0,
      0,
      0,
      0,
      fn(
        input,
        remaining_state,
        cal_intent_datum_shares_amount,
        cal_user_receives,
        cal_fee_shares,
        cal_cost_removed,
        return,
      ) {
        let (
          remaining_indices,
          remaining_actions,
          remaining_transfers,
          current_root,
        ) = remaining_state
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == withdrawal_intent_script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [_output_index, ..rest_of_indices] -> {
                  expect input_datum: WithdrawalIntentDatum =
                    input_inline_datum(input)

                  let WithdrawalIntentDatum { withdrawer, shares_to_redeem } =
                    input_datum

                  let new_cal_intent_datum_shares_amount =
                    cal_intent_datum_shares_amount + shares_to_redeem

                  // Calculate gross value
                  let gross_value =
                    convert_shares_to_usd(
                      shares_to_redeem,
                      total_shares,
                      vault_equity,
                    )

                  // Apply MPF action and compute cost_basis
                  expect [action, ..rest_actions] = remaining_actions
                  let mpf_key = cbor.serialise(withdrawer)

                  let (cost_basis, new_root) =
                    when action is {
                      SharesDelete { proof, old_value } -> {
                        // Total withdrawal
                        expect Some(old_data) = cbor.deserialise(old_value)
                        expect old_entry: SharesRecordEntry = old_data
                        expect shares_to_redeem == old_entry.shares
                        let cb = old_entry.total_deposited
                        let trie = mpf.from_root(current_root)
                        let new_trie =
                          mpf.delete(trie, mpf_key, old_value, proof)
                        (cb, mpf.root(new_trie))
                      }
                      SharesUpdate { from, to, to_proof } -> {
                        // Partial withdrawal
                        expect Some(from_data) = cbor.deserialise(from)
                        expect old_entry: SharesRecordEntry = from_data
                        expect old_entry.shares >= shares_to_redeem
                        let cb =
                          old_entry.total_deposited * shares_to_redeem / old_entry.shares
                        let expected_entry =
                          SharesRecordEntry {
                            shares: old_entry.shares - shares_to_redeem,
                            total_deposited: old_entry.total_deposited - cb,
                          }
                        let expected_value = cbor.serialise(expected_entry)
                        expect to == expected_value
                        let trie = mpf.from_root(current_root)
                        let new_trie =
                          mpf.update(trie, mpf_key, to_proof, from, to)
                        (cb, mpf.root(new_trie))
                      }
                      _ -> fail @"Invalid MPF action for withdrawal"
                    }

                  // Fee calculation (round UP)
                  let fee =
                    cal_per_user_operator_fee(
                      gross_value,
                      cost_basis,
                      operator_charge_percentage,
                    )
                  let fee_shares =
                    compute_fee_shares(fee, total_shares, vault_equity)
                  let user_receives = gross_value - fee

                  let new_cal_user_receives = cal_user_receives + user_receives
                  let new_cal_fee_shares = cal_fee_shares + fee_shares

                  // L2: Verify transfer amount matches calculated user_receives
                  expect [transfer_amount, ..rest_of_transfers] =
                    remaining_transfers
                  let transfer_usd_value =
                    convert_m_value_to_usd(transfer_amount, prices)
                  expect transfer_usd_value == user_receives

                  return(
                    (rest_of_indices, rest_actions, rest_of_transfers, new_root),
                    new_cal_intent_datum_shares_amount,
                    new_cal_user_receives,
                    new_cal_fee_shares,
                    cal_cost_removed + cost_basis,
                  )
                }
              }
            } else {
              return(
                remaining_state,
                cal_intent_datum_shares_amount,
                cal_user_receives,
                cal_fee_shares,
                cal_cost_removed,
              )
            }
          _ ->
            return(
              remaining_state,
              cal_intent_datum_shares_amount,
              cal_user_receives,
              cal_fee_shares,
              cal_cost_removed,
            )
        }
      },
    )
  let (remaining_indices, _, remaining_transfers, final_root) = processed_state
  when remaining_indices is {
    [] ->
      when remaining_transfers is {
        [] ->
          (
            total_intent_datum_shares_amount,
            total_user_receives,
            total_fee_shares,
            total_cost_removed,
            final_root,
          )
        _ -> fail @"More transfer amounts than withdrawal intents"
      }
    _ -> fail @"Batch L2 withdrawal intent UTxOs not fully processed"
  }
}

// Apply operator fee share MPF action after all user withdrawals
pub fn apply_operator_fee_share(
  current_root: ByteArray,
  total_fee_shares: Int,
  operator_address: Address,
  operator_action: SharesMPFAction,
) -> ByteArray {
  if total_fee_shares <= 0 {
    current_root
  } else {
    let mpf_key = cbor.serialise(operator_address)
    when operator_action is {
      SharesInsert { proof, new_value } -> {
        // Operator has no existing entry
        let expected_entry =
          SharesRecordEntry { shares: total_fee_shares, total_deposited: 0 }
        let expected_value = cbor.serialise(expected_entry)
        expect new_value == expected_value
        let trie = mpf.from_root(current_root)
        let new_trie = mpf.insert(trie, mpf_key, new_value, proof)
        mpf.root(new_trie)
      }
      SharesUpdate { from, to, to_proof } -> {
        // Operator has existing entry — add fee shares, total_deposited unchanged
        expect Some(from_data) = cbor.deserialise(from)
        expect old_entry: SharesRecordEntry = from_data
        let expected_entry =
          SharesRecordEntry {
            shares: old_entry.shares + total_fee_shares,
            total_deposited: old_entry.total_deposited,
          }
        let expected_value = cbor.serialise(expected_entry)
        expect to == expected_value
        let trie = mpf.from_root(current_root)
        let new_trie = mpf.update(trie, mpf_key, to_proof, from, to)
        mpf.root(new_trie)
      }
      _ -> fail @"Invalid MPF action for operator fee share"
    }
  }
}
