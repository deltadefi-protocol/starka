use aiken/cbor
use aiken/collection/dict
use aiken/crypto.{ScriptHash}
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input}
use cocktail.{input_inline_datum}
use price_oracle_utils.{convert_m_value_to_usd}
use types.{
  DepositIntentDatum, MValue, SharesInsert, SharesMPFAction, SharesRecordEntry,
  SharesUpdate,
}

pub type Scott4<a, b, c, d, result> =
  fn(a, b, c, d) -> result

pub fn list_foldl4(
  self: List<x>,
  zero_a: a,
  zero_b: b,
  zero_c: c,
  zero_d: d,
  with: fn(x, a, b, c, d, Scott4<a, b, c, d, result>) -> result,
  return: Scott4<a, b, c, d, result>,
) -> result {
  when self is {
    [] -> return(zero_a, zero_b, zero_c, zero_d)
    [x, ..xs] -> {
      let acc_a, acc_b, acc_c, acc_d <- with(x, zero_a, zero_b, zero_c, zero_d)
      list_foldl4(xs, acc_a, acc_b, acc_c, acc_d, with, return)
    }
  }
}

pub fn to_mvalue(value: Value) -> MValue {
  let data = cbor.serialise(value)
  expect Some(mvalue_raw): Option<Data> = cbor.deserialise(data)
  expect mvalue: MValue = mvalue_raw
  mvalue
}

pub fn combine_m_value(left_m_value: MValue, right_m_value: MValue) -> MValue {
  let left_dict = dict.from_pairs(left_m_value)
  let right_dict = dict.from_pairs(right_m_value)

  dict.union_with(
    left_dict,
    right_dict,
    fn(_k, v1, v2) {
      let v1_dict = dict.from_pairs(v1)
      let v2_dict = dict.from_pairs(v2)
      let all =
        dict.union_with(
          v1_dict,
          v2_dict,
          fn(_k, v_v_1, v_v_2) { Some(v_v_1 + v_v_2) },
        )
          |> dict.to_pairs()
      Some(all)
    },
  )
    |> dict.to_pairs()
}

pub fn cal_shares_amount(
  usd_value: Int,
  vault_equity: Int,
  total_shares: Int,
) -> Int {
  when total_shares is {
    0 -> fail @"Total shares cannot be zero"
    _ -> usd_value * total_shares / vault_equity
  }
}

// Process batched deposit intents with MPF merkle root transitions.
// Returns (total_m_value, total_usd_value, total_shares_added, final_merkle_root)
pub fn process_batched_deposit_intent_validation(
  inputs: List<Input>,
  indices: List<Int>,
  mpf_actions: List<SharesMPFAction>,
  vault_equity: Int,
  total_shares: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  deposit_intent_script_hash: ScriptHash,
  initial_merkle_root: ByteArray,
) -> (MValue, Int, Int, ByteArray) {
  let empty_m_value: MValue = []

  // Accumulate: (remaining_indices_and_actions, total_m_value, total_usd_value, total_shares_added)
  // We pack indices, mpf_actions, and merkle_root into the first accumulator
  let
    processed_state,
    total_intent_datum_m_value,
    total_intent_datum_usd_value,
    total_shares_added,
  <-
    list_foldl4(
      inputs,
      (indices, mpf_actions, initial_merkle_root),
      empty_m_value,
      0,
      0,
      fn(
        input,
        remaining_state,
        cal_intent_datum_m_value,
        cal_intent_datum_usd_value,
        cal_shares_added,
        return,
      ) {
        let (remaining_indices, remaining_actions, current_root) =
          remaining_state
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == deposit_intent_script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [_output_index, ..rest_of_indices] -> {
                  expect input_datum: DepositIntentDatum =
                    input_inline_datum(input)
                  let DepositIntentDatum { depositor, deposit_amount } =
                    input_datum

                  // Combine MValue
                  let new_cal_intent_datum_m_value =
                    combine_m_value(cal_intent_datum_m_value, deposit_amount)

                  // Calculate USD value
                  let intent_datum_usd_value =
                    convert_m_value_to_usd(deposit_amount, prices)
                  let new_cal_intent_datum_usd_value =
                    cal_intent_datum_usd_value + intent_datum_usd_value

                  // Calculate shares amount (round DOWN)
                  let cal_shares =
                    cal_shares_amount(
                      intent_datum_usd_value,
                      vault_equity,
                      total_shares,
                    )
                  let new_cal_shares_added = cal_shares + cal_shares_added

                  // Apply MPF action for this deposit
                  expect [action, ..rest_actions] = remaining_actions
                  let mpf_key = cbor.serialise(depositor)

                  let new_root =
                    when action is {
                      SharesInsert { proof, new_value } -> {
                        // New depositor
                        let expected_entry =
                          SharesRecordEntry {
                            shares: cal_shares,
                            total_deposited: intent_datum_usd_value,
                          }
                        let expected_value = cbor.serialise(expected_entry)
                        expect new_value == expected_value
                        let trie = mpf.from_root(current_root)
                        let new_trie =
                          mpf.insert(trie, mpf_key, new_value, proof)
                        mpf.root(new_trie)
                      }
                      SharesUpdate { from, to, to_proof } -> {
                        // Existing depositor
                        expect Some(from_data) = cbor.deserialise(from)
                        expect old_entry: SharesRecordEntry = from_data
                        let expected_entry =
                          SharesRecordEntry {
                            shares: old_entry.shares + cal_shares,
                            total_deposited: old_entry.total_deposited + intent_datum_usd_value,
                          }
                        let expected_value = cbor.serialise(expected_entry)
                        expect to == expected_value
                        let trie = mpf.from_root(current_root)
                        let new_trie =
                          mpf.update(trie, mpf_key, to_proof, from, to)
                        mpf.root(new_trie)
                      }
                      _ -> fail @"Invalid MPF action for deposit"
                    }

                  return(
                    (rest_of_indices, rest_actions, new_root),
                    new_cal_intent_datum_m_value,
                    new_cal_intent_datum_usd_value,
                    new_cal_shares_added,
                  )
                }
              }
            } else {
              return(
                remaining_state,
                cal_intent_datum_m_value,
                cal_intent_datum_usd_value,
                cal_shares_added,
              )
            }
          _ ->
            return(
              remaining_state,
              cal_intent_datum_m_value,
              cal_intent_datum_usd_value,
              cal_shares_added,
            )
        }
      },
    )
  let (remaining_indices, _, final_root) = processed_state
  when remaining_indices is {
    [] ->
      (
        total_intent_datum_m_value,
        total_intent_datum_usd_value,
        total_shares_added,
        final_root,
      )
    _ -> fail @"Batch deposit intent UTxOs not fully processed"
  }
}
