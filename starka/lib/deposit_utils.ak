use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use aiken/primitive/bytearray
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, Value, quantity_of}
use cardano/transaction.{Input, Output}
use cocktail.{input_inline_datum}
use types.{DepositIntentDatum, MValue}

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

pub fn convert_m_value_to_usd(
  m_value: MValue,
  prices: Pairs<PolicyId, Int>,
) -> Int {
  list.foldl(
    m_value,
    0,
    fn(policy_pair: Pair<PolicyId, Pairs<AssetName, Int>>, acc: Int) {
      list.foldl(
        policy_pair.2nd,
        acc,
        fn(asset_pair: Pair<AssetName, Int>, nested_acc: Int) {
          expect Some(price) =
            prices
              |> pairs.get_first(
                  bytearray.concat(policy_pair.1st, asset_pair.1st),
                )
          nested_acc + price * asset_pair.2nd
        },
      )
    },
  )
}

pub fn cal_lp_token_amount(
  usd_value: Int,
  vault_balance: Int,
  total_lp: Int,
  operator_fee: Int,
  lp_decimal: Int,
) -> Int {
  when total_lp is {
    0 -> usd_value * lp_decimal
    _ -> usd_value * total_lp / ( vault_balance - operator_fee )
  }
}

// 1. sum up intent_datum_m_value
// 2. sum up intent_datum_m_value in usd
// 3. sum up lp_token sent
// 4. output lp_token to address in intent_datum

pub fn process_batched_deposit_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: List<Int>,
  vault_balance: Int,
  total_lp: Int,
  operator_fee: Int,
  prices: Pairs<ByteArray, Int>,
  deposit_intent_script_hash: ScriptHash,
  lp_token: PolicyId,
  lp_decimal: Int,
) -> (MValue, Int, Int) {
  let empty_m_value: MValue = []
  let
    processed_indices,
    total_intent_datum_m_value,
    total_intent_datum_usd_value,
    total_lp_token_sent,
  <-
    list_foldl4(
      inputs,
      indices,
      empty_m_value,
      0,
      0,
      fn(
        input,
        remaining_indices,
        cal_intent_datum_m_value,
        cal_intent_datum_usd_value,
        cal_lp_token_sent,
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
                  // - Combine intent value with total intent value in usd
                  let intent_datum_usd_value =
                    convert_m_value_to_usd(amount, prices)
                  let new_cal_intent_datum_usd_value =
                    cal_intent_datum_usd_value + intent_datum_usd_value
                  // - Calculate LP Token sent
                  // - Combine LP Token sent with total LP Token sent
                  let cal_lp_sent =
                    cal_lp_token_amount(
                      intent_datum_usd_value,
                      vault_balance,
                      total_lp,
                      operator_fee,
                      lp_decimal,
                    )
                  let new_cal_lp_token_sent = cal_lp_sent + cal_lp_token_sent
                  // - Check the output value and address
                  let output_check =
                    quantity_of(out_utxo.value, lp_token, "") == cal_lp_sent && out_utxo.address == lp_address
                  if output_check {
                    return(
                      rest_of_indices,
                      new_cal_intent_datum_m_value,
                      new_cal_intent_datum_usd_value,
                      new_cal_lp_token_sent,
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
                cal_lp_token_sent,
              )
            }
          _ ->
            // - Not a script address, skip
            return(
              remaining_indices,
              cal_intent_datum_m_value,
              cal_intent_datum_usd_value,
              cal_lp_token_sent,
            )
        }
      },
    )
  when processed_indices is {
    [] ->
      (
        total_intent_datum_m_value,
        total_intent_datum_usd_value,
        total_lp_token_sent,
      )
    _ -> fail @"Batch deposit intent UTxOs not fully processed"
  }
}
