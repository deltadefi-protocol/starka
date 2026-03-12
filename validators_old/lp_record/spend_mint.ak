use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use types.{
  BurnLPRecord, LPRecordDatum, LPRecordMintRedeemer, MintLPRecord,
  VaultOracleDatum,
}
use utils.{check_any_policy_burned, get_vault_oracle_datum}

validator lp_record(vault_oracle_nft: PolicyId) {
  spend(
    _datum: Option<LPRecordDatum>,
    _redeemer: Data,
    _input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { reference_inputs, mint, .. } = self
    let vault_oracle_datum: VaultOracleDatum =
      reference_inputs |> get_vault_oracle_datum(vault_oracle_nft)

    let deposit_intent_burned =
      check_any_policy_burned(
        mint,
        vault_oracle_datum.deposit_intent_script_hash,
      )
    let withdrawal_intent_burned =
      check_any_policy_burned(
        mint,
        vault_oracle_datum.withdrawal_intent_script_hash,
      )

    deposit_intent_burned || withdrawal_intent_burned
  }

  mint(
    redeemer: LPRecordMintRedeemer,
    _policy_id: PolicyId,
    self: Transaction,
  ) {
    let Transaction { reference_inputs, mint, .. } = self
    let vault_oracle_datum: VaultOracleDatum =
      reference_inputs |> get_vault_oracle_datum(vault_oracle_nft)

    when redeemer is {
      MintLPRecord ->
        check_any_policy_burned(
          mint,
          vault_oracle_datum.deposit_intent_script_hash,
        )
      BurnLPRecord ->
        check_any_policy_burned(
          mint,
          vault_oracle_datum.withdrawal_intent_script_hash,
        )
    }
  }

  else(_) {
    fail
  }
}
