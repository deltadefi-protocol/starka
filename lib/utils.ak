use aiken/collection/list
use aiken/collection/pairs.{has_key}
use aiken/crypto.{
  ScriptHash, VerificationKey, VerificationKeyHash, blake2b_224,
  verify_ed25519_signature,
}
use cardano/address.{Credential, Script}
use cardano/assets.{Lovelace, PolicyId, Value, quantity_of}
use cardano/transaction.{InlineDatum, Input, Redeemer, ScriptPurpose}
use cocktail.{input_inline_datum}
use hydra_dex/types.{AppOracleDatum} as dd_types
use types.{BurnIntent, IntentRedeemer, VaultDatum}

pub fn get_vault_datum(inputs: List<Input>, vault_nft: PolicyId) -> VaultDatum {
  expect Some(vault_input) =
    inputs
      |> list.find(
          fn(input: Input) {
            quantity_of(input.output.value, vault_nft, "") == 1
          },
        )
  expect datum: VaultDatum = input_inline_datum(vault_input)
  datum
}

pub fn get_vault_input(inputs: List<Input>, vault_nft: PolicyId) -> Input {
  expect Some(vault_input) =
    inputs
      |> list.find(
          fn(input: Input) {
            quantity_of(input.output.value, vault_nft, "") == 1
          },
        )
  vault_input
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

  expect InlineDatum(oracle_input_data) = oracle_input.output.datum
  expect oracle_input_datum: AppOracleDatum = oracle_input_data
  oracle_input_datum
}

pub fn check_mint_redeemer_is_burn_intent(
  mint_purpose: ScriptPurpose,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
) -> Bool {
  expect Some(mint_redeemer_data) = redeemers |> pairs.get_first(mint_purpose)
  expect mint_redeemer: IntentRedeemer = mint_redeemer_data

  when mint_redeemer is {
    BurnIntent(_, _, _, _) -> True
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

pub fn withdrawal_script_validated(
  withdrawals: Pairs<Credential, Lovelace>,
  withdrawal_script_hash: ScriptHash,
) -> Bool {
  withdrawals
    |> has_key(Script(withdrawal_script_hash))
}

pub fn check_any_policy_burned(mint: Value, policy_id: PolicyId) -> Bool {
  quantity_of(mint, policy_id, "") < 0
}
