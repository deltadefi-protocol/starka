use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Input, Output}
use cocktail.{input_inline_datum, output_inline_datum}
use types.{LPRecordDatum, WithdrawalIntentDatum}
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

pub fn convert_lp_to_usd(
  lp_amount: Int,
  total_lp: Int,
  vault_balance: Int,
) -> Int {
  lp_amount * vault_balance / total_lp
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
    profit * operator_charge_percentage / 100
  }
}

pub fn check_output_value_equal_to_lp_usd_value(
  output_value: Value,
  lp_usd_value: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
) -> Bool {
  assets.reduce(
    output_value,
    0,
    fn(policy_id, asset_name, amount, acc) {
      expect Some(price) = prices |> pairs.get_first((policy_id, asset_name))

      acc + amount * price
    },
  ) == lp_usd_value
}

// 1. sum up intent_datum_lp_amount
// 2. sum up user receives (withdrawal_value - fee)
// 3. sum up total fee retained in vault
// 4. count LP Records burned (total withdrawals)
// 5. validate user asset output per intent
// 6. validate LP Record output per intent (partial withdrawal)

pub fn process_batched_withdrawal_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: List<Int>,
  lp_record_output_indices: List<Int>,
  vault_balance: Int,
  total_lp: Int,
  operator_charge_percentage: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  withdrawal_intent_script_hash: ScriptHash,
  lp_record_script_hash: ScriptHash,
) -> (Int, Int, Int, Int, Int) {
  let lp_record_inputs =
    collect_lp_record_inputs(inputs, lp_record_script_hash)

  // First accumulator is a triple: (remaining_indices, remaining_lp_record_indices, total_cost_removed)
  let
    processed_triple,
    total_intent_datum_lp_amount,
    total_user_receives,
    total_fee_retained,
    total_lp_records_burned,
  <-
    list_foldl5(
      inputs,
      (indices, lp_record_output_indices, 0),
      0,
      0,
      0,
      0,
      fn(
        input,
        remaining_triple,
        cal_intent_datum_lp_amount,
        cal_user_receives,
        cal_fee_retained,
        cal_lp_records_burned,
        return,
      ) {
        let (remaining_indices, remaining_lp_indices, cal_cost_removed) =
          remaining_triple
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == withdrawal_intent_script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [output_index, ..rest_of_indices] -> {
                  expect Some(out_utxo) = outputs |> list.at(output_index)
                  expect input_datum: WithdrawalIntentDatum =
                    input_inline_datum(input)

                  let WithdrawalIntentDatum { lp_address, amount } =
                    input_datum

                  // - Find the LP Record for this withdrawer
                  expect Some(lp_record) =
                    find_lp_record_by_address(lp_record_inputs, lp_address)
                  expect lp_record.lp >= amount

                  // - Combine intent datum LP amount
                  let new_cal_intent_datum_lp_amount =
                    cal_intent_datum_lp_amount + amount

                  // - Calculate per-user fee
                  let withdrawal_value =
                    convert_lp_to_usd(amount, total_lp, vault_balance)
                  let cost_basis = lp_record.cost * amount / lp_record.lp
                  let fee =
                    cal_per_user_operator_fee(
                      withdrawal_value,
                      cost_basis,
                      operator_charge_percentage,
                    )
                  let user_receives = withdrawal_value - fee

                  let new_cal_user_receives = cal_user_receives + user_receives
                  let new_cal_fee_retained = cal_fee_retained + fee

                  // - Check the output value and address
                  let output_check =
                    check_output_value_equal_to_lp_usd_value(
                      out_utxo.value,
                      user_receives,
                      prices,
                    ) && out_utxo.address == lp_address

                  // - Handle LP Record: total vs partial withdrawal
                  let (lp_record_check, burned_delta, new_remaining_lp_indices) =
                    if amount == lp_record.lp {
                      // Total withdrawal: LP Record burned (no output to check)
                      (True, 1, remaining_lp_indices)
                    } else {
                      // Partial withdrawal: validate LP Record output
                      expect [lp_record_out_index, ..rest_lp_indices] =
                        remaining_lp_indices
                      expect Some(lp_record_out) =
                        outputs |> list.at(lp_record_out_index)
                      expect lp_record_out_datum: LPRecordDatum =
                        output_inline_datum(lp_record_out)
                      let is_at_lp_record_address =
                        lp_record_out.address == from_script(
                          lp_record_script_hash,
                        )
                      let is_datum_correct =
                        lp_record_out_datum.address == lp_address && lp_record_out_datum.lp == lp_record.lp - amount && lp_record_out_datum.cost == lp_record.cost - cost_basis
                      (
                        is_at_lp_record_address && is_datum_correct,
                        0,
                        rest_lp_indices,
                      )
                    }

                  if output_check && lp_record_check {
                    return(
                      (
                        rest_of_indices,
                        new_remaining_lp_indices,
                        cal_cost_removed + cost_basis,
                      ),
                      new_cal_intent_datum_lp_amount,
                      new_cal_user_receives,
                      new_cal_fee_retained,
                      cal_lp_records_burned + burned_delta,
                    )
                  } else {
                    fail @"Withdrawal intent output incorrect"
                  }
                }
              }
            } else {
              return(
                remaining_triple,
                cal_intent_datum_lp_amount,
                cal_user_receives,
                cal_fee_retained,
                cal_lp_records_burned,
              )
            }
          _ ->
            return(
              remaining_triple,
              cal_intent_datum_lp_amount,
              cal_user_receives,
              cal_fee_retained,
              cal_lp_records_burned,
            )
        }
      },
    )
  let (remaining_indices, _, total_cost_removed) = processed_triple
  when remaining_indices is {
    [] ->
      (
        total_intent_datum_lp_amount,
        total_user_receives,
        total_fee_retained,
        total_lp_records_burned,
        total_cost_removed,
      )
    _ -> fail @"Batch withdrawal intent UTxOs not fully processed"
  }
}
