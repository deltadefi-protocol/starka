use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{
  ScriptHash, VerificationKey, VerificationKeyHash, blake2b_224,
  verify_ed25519_signature,
}
use aiken/primitive/bytearray
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, quantity_of}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, Redeemer, ScriptPurpose,
}
use cocktail.{outputs_at_with_policy}
use cocktail/vodka_outputs.{output_inline_datum}
use types.{
  AppOracleDatum, BurnIntent, DepositIntentDatum, IntentRedeemer, MValue,
  VaultOracleDatum,
}

pub fn get_app_oracle_datum(
  reference_inputs: List<Input>,
  oracle_nft: PolicyId,
) -> AppOracleDatum {
  expect Some(oracle_input) =
    reference_inputs
      |> list.find(
          fn(ref_input: Input) {
            quantity_of(ref_input.output.value, oracle_nft, "") == 1
          },
        )

  let oracle_input_data: Data =
    when oracle_input.output.datum is {
      NoDatum -> fail @"Oracle input does not contain any datum"
      DatumHash(_) -> fail @"Oracle input datum must be inlined"
      InlineDatum(data) -> data
    }
  expect oracle_input_datum: AppOracleDatum = oracle_input_data
  oracle_input_datum
}

pub fn get_vault_oracle_datum(
  inputs: List<Input>,
  oracle_nft: PolicyId,
) -> VaultOracleDatum {
  expect Some(oracle_input) =
    inputs
      |> list.find(
          fn(ref_input: Input) {
            quantity_of(ref_input.output.value, oracle_nft, "") == 1
          },
        )

  let oracle_input_data: Data =
    when oracle_input.output.datum is {
      NoDatum -> fail @"Oracle input does not contain any datum"
      DatumHash(_) -> fail @"Oracle input datum must be inlined"
      InlineDatum(data) -> data
    }
  expect oracle_input_datum: VaultOracleDatum = oracle_input_data
  oracle_input_datum
}

pub fn check_mint_redeemer_is_burn(
  mint_purpose: ScriptPurpose,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
) -> Bool {
  expect Some(mint_redeemer_data) = redeemers |> pairs.get_first(mint_purpose)
  expect mint_redeemer: IntentRedeemer = mint_redeemer_data

  when mint_redeemer is {
    BurnIntent(_, _, _) -> True
    _ -> False
  }
}

pub fn verify_pub_keys(
  keys: List<VerificationKey>,
  pkhs: List<VerificationKeyHash>,
) -> Bool {
  list.map2(
    keys,
    pkhs,
    fn(key: VerificationKey, pkh: VerificationKeyHash) {
      blake2b_224(key) == pkh
    },
  )
    |> list.all(fn(x: Bool) { x })
}

pub fn verify_pub_keys_indexed(
  keys: List<VerificationKey>,
  pkhs: List<VerificationKeyHash>,
) -> Bool {
  list.indexed_foldr(
    keys,
    True,
    fn(i: Int, key: VerificationKey, acc: Bool) {
      expect Some(pkh) = list.at(pkhs, i)
      acc && blake2b_224(key) == pkh
    },
  )
}

pub fn verify_signatures(
  keys: List<VerificationKey>,
  msg: ByteArray,
  sigs: List<ByteArray>,
) -> Bool {
  when keys is {
    [key, ..rest_keys] -> {
      expect [sig, ..rest_sigs] = sigs
      when verify_ed25519_signature(key, msg, sig) is {
        True -> verify_signatures(rest_keys, msg, rest_sigs)?
        False -> False
      }
    }
    [] -> True
  }
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

pub fn convert_m_value_to_usdm(
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
              |> pairs.get_first(bytearray.concat(policy_pair.1st, asset_pair.1st))
          nested_acc + price * 1000000 * asset_pair.2nd
        },
      )
    },
  )
}

pub fn cal_lp_token_amount(
  usdm_value: Int,
  vault_balance: Int,
  total_lp: Int,
) -> Int {
  usdm_value / vault_balance * total_lp
}

// 1. sum up intent_datum_m_value
// 2. sum up intent_datum_m_value in usdm
// 3. sum up lp_token sent
// 4. output lp_token to address in intent_datum

pub fn process_batched_deposit_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: List<Int>,
  vault_balance: Int,
  total_lp: Int,
  prices: Pairs<ByteArray, Int>,
  script_hash: ScriptHash,
  lp_token: PolicyId,
  pluggable_logic: ByteArray,
) -> (MValue, Int, Int) {
  let empty_m_value: MValue = []
  let
    processed_indices,
    total_intent_datum_m_value,
    total_intent_datum_usdm_value,
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
        cal_intent_datum_usdm_value,
        cal_lp_token_sent,
        return,
      ) {
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [output_index, ..rest_of_indices] -> {
                  expect Some(out_utxo) = outputs |> list.at(output_index)
                  expect output_datum: DepositIntentDatum =
                    output_inline_datum(out_utxo)

                  let DepositIntentDatum { lp_address, amount } = output_datum

                  let new_cal_intent_datum_m_value =
                    combine_m_value(cal_intent_datum_m_value, amount)

                  let intent_datum_usdm_value =
                    convert_m_value_to_usdm(amount, prices)
                  let new_cal_intent_datum_usdm_value =
                    cal_intent_datum_usdm_value + intent_datum_usdm_value

                  let cal_lp_sent =
                    cal_lp_token_amount(
                      cal_intent_datum_usdm_value,
                      vault_balance,
                      total_lp,
                    )
                  let new_cal_lp_token_sent = cal_lp_sent + cal_lp_token_sent

                  let output_check =
                    quantity_of(out_utxo.value, lp_token, pluggable_logic) == cal_lp_sent && out_utxo.address == lp_address
                  if output_check {
                    return(
                      rest_of_indices,
                      new_cal_intent_datum_m_value,
                      new_cal_intent_datum_usdm_value,
                      new_cal_lp_token_sent,
                    )
                  } else {
                    fail @"Deposit intent output incorrect"
                  }
                }
              }
            } else {
              return(
                remaining_indices,
                cal_intent_datum_m_value,
                cal_intent_datum_usdm_value,
                cal_lp_token_sent,
              )
            }
          _ ->
            return(
              remaining_indices,
              cal_intent_datum_m_value,
              cal_intent_datum_usdm_value,
              cal_lp_token_sent,
            )
        }
      },
    )
  when processed_indices is {
    [] ->
      (
        total_intent_datum_m_value,
        total_intent_datum_usdm_value,
        total_lp_token_sent,
      )
    _ -> fail @"Batch deposit intent UTxOs not fully processed"
  }
}

pub fn cal_operator_fee(
  vault_balance: Int,
  hwm_lp_value: Int,
  operator_charge,
) -> Int {
  if vault_balance <= hwm_lp_value {
    0
  } else {
    ( vault_balance - hwm_lp_value ) * operator_charge
  }
}
