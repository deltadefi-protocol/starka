use cardano/transaction.{Mint, OutputReference, Transaction}
use types.{
  ProcessDeposit, ProcessWithdrawal, VaultOracleDatum, VaultOracleRedeemer,
}
use utils.{check_mint_redeemer_is_burn}

validator vault_oracle {
  spend(
    datum_opt: Option<VaultOracleDatum>,
    redeemer: VaultOracleRedeemer,
    _input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { redeemers, .. } = self

    when datum_opt is {
      Some(datum) -> {
        let VaultOracleDatum {
          deposit_intent_script_hash,
          withdrawal_intent_script_hash,
          ..
        } = datum

        let mint_purpose =
          when redeemer is {
            ProcessDeposit -> Mint(deposit_intent_script_hash)

            ProcessWithdrawal -> Mint(withdrawal_intent_script_hash)
          }

        check_mint_redeemer_is_burn(mint_purpose, redeemers)?
      }

      None -> False
    }
  }

  else(_) {
    fail
  }
}
