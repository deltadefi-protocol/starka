use cardano/assets.{PolicyId, negate, without_lovelace}
use cardano/transaction.{OutputReference, Transaction, find_input}
use cocktail.{token_minted}
use types.{VaultOracleDatum}

validator vault_oracle(oracle_nft: PolicyId) {
  spend(
    datum_opt: Option<VaultOracleDatum>,
    _redeemer: Data,
    input: OutputReference,
    tx: Transaction,
  ) {
    expect Some(datum) = datum_opt
    let VaultOracleDatum { vault_state_script_hash, .. } = datum

    expect Some(own_input) = find_input(tx.inputs, input)
    let oracle_nft_value = without_lovelace(own_input.output.value)
    let is_oracle_nft_burnt =
      assets.match(tx.mint, negate(oracle_nft_value), ==)
    let is_vault_inactive = !datum.is_active

    is_oracle_nft_burnt? && is_vault_inactive?
  }

  else(_) {
    fail
  }
}
