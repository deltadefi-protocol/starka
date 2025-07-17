use aiken/collection/list
use aiken/collection/pairs
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Redeemer, ScriptPurpose,
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
