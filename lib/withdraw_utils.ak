use aiken/cbor
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input, Output}
use cocktail.{input_inline_datum}
use hydra_dex/types.{Account, UserTradeAccount} as dd_types
use types.{
  SharesDelete, SharesInsert, SharesMPFAction, SharesRecordEntry, SharesUpdate,
  WithdrawalIntentDatum,
}

pub type Scott6<a, b, c, d, e, f, result> =
  fn(a, b, c, d, e, f) -> result

pub fn list_foldl6(
  self: List<x>,
  zero_a: a,
  zero_b: b,
  zero_c: c,
  zero_d: d,
  zero_e: e,
  zero_f: f,
  with: fn(x, a, b, c, d, e, f, Scott6<a, b, c, d, e, f, result>) -> result,
  return: Scott6<a, b, c, d, e, f, result>,
) -> result {
  when self is {
    [] -> return(zero_a, zero_b, zero_c, zero_d, zero_e, zero_f)
    [x, ..xs] -> {
      let
        acc_a,
        acc_b,
        acc_c,
        acc_d,
        acc_e,
        acc_f,
      <- with(x, zero_a, zero_b, zero_c, zero_d, zero_e, zero_f)
      list_foldl6(xs, acc_a, acc_b, acc_c, acc_d, acc_e, acc_f, with, return)
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
// Returns (total_shares_amount, total_user_receives, total_fee_shares, total_cost_removed, operator_shares_withdrawn, final_merkle_root)
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
  operator_account: Account,
) -> (Int, Int, Int, Int, Int, ByteArray) {
  // Accumulate: (state_triple, total_shares, total_user_receives, total_fee_shares, total_cost_removed, operator_shares_withdrawn)
  let
    processed_state,
    total_intent_datum_shares_amount,
    total_user_receives,
    total_fee_shares,
    total_cost_removed,
    operator_shares_withdrawn,
  <-
    list_foldl6(
      inputs,
      (indices, mpf_actions, initial_merkle_root),
      0,
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
        cal_operator_shares_withdrawn,
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
                  // Extract Account from UserAccount and use as MPF key
                  expect UserTradeAccount { account: withdrawer_acc, .. } =
                    withdrawer
                  let mpf_key = cbor.serialise(withdrawer_acc)

                  // Track if withdrawer is operator
                  let new_cal_operator_shares_withdrawn =
                    if withdrawer_acc == operator_account {
                      cal_operator_shares_withdrawn + shares_to_redeem
                    } else {
                      cal_operator_shares_withdrawn
                    }

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
                      SharesUpdate { from, to_proof } -> {
                        // Partial withdrawal - compute to value
                        expect Some(from_data) = cbor.deserialise(from)
                        expect old_entry: SharesRecordEntry = from_data
                        expect old_entry.shares >= shares_to_redeem
                        let cb =
                          old_entry.total_deposited * shares_to_redeem / old_entry.shares
                        let new_entry =
                          SharesRecordEntry {
                            shares: old_entry.shares - shares_to_redeem,
                            total_deposited: old_entry.total_deposited - cb,
                          }
                        let to = cbor.serialise(new_entry)
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

                  let output_check =
                    check_output_value_equal_to_shares_usd_value(
                      out_utxo.value,
                      user_receives,
                      prices,
                    ) && out_utxo.address.payment_credential == withdrawer_acc.master_key

                  if output_check {
                    return(
                      (rest_of_indices, rest_actions, new_root),
                      new_cal_intent_datum_shares_amount,
                      new_cal_user_receives,
                      new_cal_fee_shares,
                      cal_cost_removed + cost_basis,
                      new_cal_operator_shares_withdrawn,
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
                cal_operator_shares_withdrawn,
              )
            }
          _ ->
            return(
              remaining_state,
              cal_intent_datum_shares_amount,
              cal_user_receives,
              cal_fee_shares,
              cal_cost_removed,
              cal_operator_shares_withdrawn,
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
        operator_shares_withdrawn,
        final_root,
      )
    _ -> fail @"Batch withdrawal intent UTxOs not fully processed"
  }
}

// Apply operator fee share MPF action after all user withdrawals
pub fn apply_operator_fee_share(
  current_root: ByteArray,
  total_fee_shares: Int,
  operator_account: Account,
  operator_action: SharesMPFAction,
) -> ByteArray {
  if total_fee_shares <= 0 {
    current_root
  } else {
    // Use Account directly as MPF key
    let mpf_key = cbor.serialise(operator_account)
    when operator_action is {
      SharesInsert { proof } -> {
        // Operator has no existing entry - compute new_value
        let new_entry =
          SharesRecordEntry { shares: total_fee_shares, total_deposited: 0 }
        let new_value = cbor.serialise(new_entry)
        let trie = mpf.from_root(current_root)
        let new_trie = mpf.insert(trie, mpf_key, new_value, proof)
        mpf.root(new_trie)
      }
      SharesUpdate { from, to_proof } -> {
        // Operator has existing entry — add fee shares, total_deposited unchanged
        expect Some(from_data) = cbor.deserialise(from)
        expect old_entry: SharesRecordEntry = from_data
        let new_entry =
          SharesRecordEntry {
            shares: old_entry.shares + total_fee_shares,
            total_deposited: old_entry.total_deposited,
          }
        let to = cbor.serialise(new_entry)
        let trie = mpf.from_root(current_root)
        let new_trie = mpf.update(trie, mpf_key, to_proof, from, to)
        mpf.root(new_trie)
      }
      _ -> fail @"Invalid MPF action for operator fee share"
    }
  }
}
