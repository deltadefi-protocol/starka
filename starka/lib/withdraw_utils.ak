use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/primitive/bytearray
use cardano/address.{Script}
use cardano/assets.{Value}
use cardano/transaction.{Input, Output}
use cocktail.{input_inline_datum}
use types.{WithdrawalIntentDatum}

pub type Scott3<a, b, c, result> =
  fn(a, b, c) -> result

pub fn list_foldl3(
  self: List<x>,
  zero_a: a,
  zero_b: b,
  zero_c: c,
  with: fn(x, a, b, c, Scott3<a, b, c, result>) -> result,
  return: Scott3<a, b, c, result>,
) -> result {
  when self is {
    [] -> return(zero_a, zero_b, zero_c)
    [x, ..xs] -> {
      let acc_a, acc_b, acc_c <- with(x, zero_a, zero_b, zero_c)
      list_foldl3(xs, acc_a, acc_b, acc_c, with, return)
    }
  }
}

pub fn convert_lp_to_usdm(
  lp_amount: Int,
  total_lp: Int,
  vault_balance: Int,
  operator_fee: Int,
) -> Int {
  lp_amount * ( vault_balance - operator_fee ) / total_lp
}

pub fn check_output_value_equal_to_lp_usdm_value(
  output_value: Value,
  lp_usdm_value: Int,
  prices: Pairs<ByteArray, Int>,
) -> Bool {
  let prices_dict = dict.from_pairs(prices)
  assets.reduce(
    output_value,
    0,
    fn(policy_id, asset_name, amount, acc) {
      expect Some(price) =
        prices_dict |> dict.get(bytearray.concat(policy_id, asset_name))

      acc + amount * price
    },
  ) == lp_usdm_value
}

// attention: init mint value*10e6
pub fn cal_lp_token_amount(
  usdm_value: Int,
  vault_balance: Int,
  total_lp: Int,
  operator_fee: Int,
) -> Int {
  if total_lp == 0 {
    usdm_value * 1000000
  } else {
    usdm_value * total_lp / ( vault_balance - operator_fee )
  }
}

// 1. sum up intent_datum_lp_amount for mint and update total_lp
// 2. sum up intent_datum_lp_value in usdm for update hwm_lp_value
// 3. output usdm/ada to address in intent_datum

pub fn process_batched_withdrawal_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: List<Int>,
  vault_balance: Int,
  total_lp: Int,
  operator_fee: Int,
  prices: Pairs<ByteArray, Int>,
  script_hash: ScriptHash,
) -> (Int, Int) {
  let
    processed_indices,
    total_intent_datum_lp_amount,
    total_intent_datum_lp_usdm_value,
  <-
    list_foldl3(
      inputs,
      indices,
      0,
      0,
      fn(
        input,
        remaining_indices,
        cal_intent_datum_lp_amount,
        cal_intent_datum_lp_usdm_value,
        return,
      ) {
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [output_index, ..rest_of_indices] -> {
                  expect Some(out_utxo) = outputs |> list.at(output_index)
                  expect input_datum: WithdrawalIntentDatum =
                    input_inline_datum(input)

                  let WithdrawalIntentDatum { lp_address, amount } = input_datum

                  let new_cal_intent_datum_lp_amount =
                    cal_intent_datum_lp_amount + amount
                  let intent_datum_lp_usdm_value =
                    convert_lp_to_usdm(
                      amount,
                      total_lp,
                      vault_balance,
                      operator_fee,
                    )
                  let new_cal_intent_datum_lp_usdm_value =
                    cal_intent_datum_lp_usdm_value + intent_datum_lp_usdm_value

                  let output_check =
                    check_output_value_equal_to_lp_usdm_value(
                      out_utxo.value,
                      intent_datum_lp_usdm_value,
                      prices,
                    ) && out_utxo.address == lp_address
                  if output_check {
                    return(
                      rest_of_indices,
                      new_cal_intent_datum_lp_amount,
                      new_cal_intent_datum_lp_usdm_value,
                    )
                  } else {
                    fail @"Withdrawal intent output incorrect"
                  }
                }
              }
            } else {
              return(
                remaining_indices,
                cal_intent_datum_lp_amount,
                cal_intent_datum_lp_usdm_value,
              )
            }
          _ ->
            return(
              remaining_indices,
              cal_intent_datum_lp_amount,
              cal_intent_datum_lp_usdm_value,
            )
        }
      },
    )
  when processed_indices is {
    [] -> (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value)
    _ -> fail @"Batch withdrawal intent UTxOs not fully processed"
  }
}
