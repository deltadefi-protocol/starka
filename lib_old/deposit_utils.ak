use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input, Output}
use cocktail.{input_inline_datum, output_inline_datum}
use price_oracle_utils.{convert_m_value_to_usd}
use types.{DepositIntentDatum, LPRecordDatum, MValue}
use utils.{collect_lp_record_inputs, find_lp_record_by_address}

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
      let acc_a, acc_b, acc_c, acc_d, acc_e <-
        with(x, zero_a, zero_b, zero_c, zero_d, zero_e)
      list_foldl5(xs, acc_a, acc_b, acc_c, acc_d, acc_e, with, return)
    }
  }
}

pub fn to_mvalue(value: Value) -> MValue {
  let data = cbor.serialise(value)
  expect Some(mvalue_raw): Option<Data> = cbor.deserialise(data)
  expect mvalue: MValue = mvalue_raw
  mvalue
}

// attention: AssetName sorted in ascending lexicographic
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

pub fn cal_lp_amount(
  usd_value: Int,
  vault_balance: Int,
  total_lp: Int,
) -> Int {
  when total_lp is {
    0 -> fail @"Total LP cannot be zero"
    _ -> usd_value * total_lp / vault_balance
  }
}

// 1. sum up intent_datum_m_value
// 2. sum up intent_datum_m_value in usd
// 3. sum up lp amount added
// 4. validate LP Record output per intent (new or existing depositor)
// 5. count new LP Records minted

pub fn process_batched_deposit_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: List<Int>,
  vault_balance: Int,
  total_lp: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  deposit_intent_script_hash: ScriptHash,
  lp_record_script_hash: ScriptHash,
) -> (MValue, Int, Int, Int) {
  let empty_m_value: MValue = []
  let lp_record_inputs =
    collect_lp_record_inputs(inputs, lp_record_script_hash)

  let
    processed_indices,
    total_intent_datum_m_value,
    total_intent_datum_usd_value,
    total_lp_added,
    new_lp_record_count,
  <-
    list_foldl5(
      inputs,
      indices,
      empty_m_value,
      0,
      0,
      0,
      fn(
        input,
        remaining_indices,
        cal_intent_datum_m_value,
        cal_intent_datum_usd_value,
        cal_lp_added,
        cal_new_lp_records,
        return,
      ) {
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == deposit_intent_script_hash {
              // Found the deposit intent script address
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [output_index, ..rest_of_indices] -> {
                  expect Some(out_utxo) = outputs |> list.at(output_index)
                  expect input_datum: DepositIntentDatum =
                    input_inline_datum(input)

                  let DepositIntentDatum { lp_address, amount } = input_datum

                  // - Combine MValue in intent with total intent value
                  let new_cal_intent_datum_m_value =
                    combine_m_value(cal_intent_datum_m_value, amount)

                  // - Calculate intent value in usd
                  let intent_datum_usd_value =
                    convert_m_value_to_usd(amount, prices)
                  let new_cal_intent_datum_usd_value =
                    cal_intent_datum_usd_value + intent_datum_usd_value

                  // - Calculate LP amount for this deposit
                  let cal_lp =
                    cal_lp_amount(
                      intent_datum_usd_value,
                      vault_balance,
                      total_lp,
                    )
                  let new_cal_lp_added = cal_lp + cal_lp_added

                  // - Validate LP Record output
                  expect lp_record_datum: LPRecordDatum =
                    output_inline_datum(out_utxo)
                  let is_output_at_lp_record_address =
                    out_utxo.address == from_script(lp_record_script_hash)
                  let is_address_correct =
                    lp_record_datum.address == lp_address

                  // - Check if new or existing depositor
                  let existing_record =
                    find_lp_record_by_address(lp_record_inputs, lp_address)
                  let (is_lp_correct, is_cost_correct, new_records_delta) =
                    when existing_record is {
                      Some(old_record) ->
                        // Existing depositor: verify updated datum
                        (
                          lp_record_datum.lp == old_record.lp + cal_lp,
                          lp_record_datum.cost == old_record.cost + intent_datum_usd_value,
                          0,
                        )
                      None ->
                        // New depositor: verify fresh datum
                        (
                          lp_record_datum.lp == cal_lp,
                          lp_record_datum.cost == intent_datum_usd_value,
                          1,
                        )
                    }

                  let output_check =
                    is_output_at_lp_record_address && is_address_correct && is_lp_correct && is_cost_correct
                  if output_check {
                    return(
                      rest_of_indices,
                      new_cal_intent_datum_m_value,
                      new_cal_intent_datum_usd_value,
                      new_cal_lp_added,
                      cal_new_lp_records + new_records_delta,
                    )
                  } else {
                    fail @"Deposit intent output incorrect"
                  }
                }
              }
            } else {
              // - Not the deposit intent script address, skip
              return(
                remaining_indices,
                cal_intent_datum_m_value,
                cal_intent_datum_usd_value,
                cal_lp_added,
                cal_new_lp_records,
              )
            }
          _ ->
            // - Not a script address, skip
            return(
              remaining_indices,
              cal_intent_datum_m_value,
              cal_intent_datum_usd_value,
              cal_lp_added,
              cal_new_lp_records,
            )
        }
      },
    )
  when processed_indices is {
    [] ->
      (
        total_intent_datum_m_value,
        total_intent_datum_usd_value,
        total_lp_added,
        new_lp_record_count,
      )
    _ -> fail @"Batch deposit intent UTxOs not fully processed"
  }
}
