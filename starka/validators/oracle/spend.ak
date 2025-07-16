use cardano/transaction.{
  Mint, OutputReference, Redeemer, Transaction, find_input,
}
use types.{VaultOracleDatum, VaultOracleRedeemer}

validator app_oracle {
  spend(
    datum_opt: Option<VaultOracleDatum>,
    redeemer: VaultOracleRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    let Transaction { mint, redeemers, .. } = self

    let mint_purpose = Mint(mint_script_hash)

    let mint_redeemer: Redeemer = redeemers |> pairs.get_first(mint_purpose)

    let tokens = mint |> assets.tokens(mint_script_hash)
  }

  else(_) {
    fail
  }
}
