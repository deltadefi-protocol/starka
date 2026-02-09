use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction}
use types.{ProcessDeposit, ProcessRedeemer, ProcessWithdrawal, VaultOracleDatum}
use utils.{check_mint_redeemer_is_burn, get_vault_oracle_datum}

validator vault_oracle(oracle_nft: PolicyId) {
  spend(
    _d: Option<VaultOracleDatum>,
    redeemer: ProcessRedeemer,
    _input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { redeemers, inputs, .. } = self
    let vault_oracle_input_datum: VaultOracleDatum =
      inputs |> get_vault_oracle_datum(oracle_nft)

    let VaultOracleDatum {
      deposit_intent_script_hash,
      withdrawal_intent_script_hash,
      ..
    } = vault_oracle_input_datum

    let mint_purpose =
      when redeemer is {
        ProcessDeposit -> Mint(deposit_intent_script_hash)
        ProcessWithdrawal -> Mint(withdrawal_intent_script_hash)
      }

    check_mint_redeemer_is_burn(mint_purpose, redeemers)?
  }

  else(_) {
    fail
  }
}
