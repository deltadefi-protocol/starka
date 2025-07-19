use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{
  ScriptHash, VerificationKey, VerificationKeyHash, blake2b_224,
  verify_ed25519_signature,
}
use cardano/address.{Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, Redeemer, ScriptPurpose,
}
use types.{AppOracleDatum, BurnIntent, IntentRedeemer, VaultOracleDatum}

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

pub fn process_batched_deposit_intent_validation(
  inputs: List<Input>,
  outputs: List<Output>,
  indices: Pairs<Int, Int>,
  vault_balance: Int,
  total_lp: Int,
  script_hash: ScriptHash,
) -> Bool {
  let
    processed_indices,
    _,
    _,
    _,
  <-
    list_foldl4(
      inputs,
      indices,
      -1,
      -1,
      0,
      fn(input, remaining_indices, in0, out0, i, return) {
        let next_i = i + 1
        when input.output.address.payment_credential is {
          Script(script) ->
            if script == script_hash {
              when remaining_indices is {
                [] -> fail @"More UTxOs are spent than specified"
                [Pair(in1, out1), ..rest_of_indices] ->
                  if i == in1 && in1 > in0 && out1 > out0 {
                    expect Some(out_utxo) = outputs |> list.at(out1)
                    if deposit_intent_validation_logic(
                      in1,
                      input,
                      out1,
                      out_utxo,
                      vault_balance,
                      total_lp,
                    ) {
                      return(rest_of_indices, in1, out1, next_i)
                    } else {
                      fail @"Validation failed"
                    }
                  } else {
                    fail @"Input and output indices must be in ascending orders"
                  }
              }
            } else {
              return(remaining_indices, in0, out0, next_i)
            }
          _ -> return(remaining_indices, in0, out0, next_i)
        }
      },
    )
  (processed_indices == [])?
}

pub fn deposit_intent_validation_logic(
  in_utxo: Output,
  out_utxo: Output,
  vault_balance: Int,
  total_lp: Int,
) -> Bool {
  expect Output {
    value: in_val,
    datum: in_dat,
    address: in_addr,
    reference_script: None,
  } = in_utxo
  expect Output {
    value: out_val,
    datum: out_dat,
    address: out_addr,
    reference_script: None,
  } = out_utxo
  True
}
