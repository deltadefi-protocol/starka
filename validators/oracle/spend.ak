use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction}
use cocktail.{token_minted}
use types.{ProcessDeposit, ProcessRedeemer, ProcessWithdrawal, VaultOracleDatum}
use utils.{check_mint_redeemer_is_burn, get_vault_oracle_datum}

validator vault_oracle(oracle_nft: PolicyId) {
  spend(
    datum_opt: Option<VaultOracleDatum>,
    _redeemer: Data,
    _input: OutputReference,
    tx: Transaction,
  ) {
    expect Some(datum) = datum_opt
    let VaultOracleDatum { vault_state_script_hash, .. } = datum

    token_minted(tx.mint, vault_state_script_hash, "", -1)?
  }

  else(_) {
    fail
  }
}
