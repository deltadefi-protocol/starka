use cardano/assets.{add, from_asset, zero}
use cardano/transaction.{Transaction, placeholder}
use mocktail.{
  complete, mint, mock_policy_id, mock_pub_key_address, mock_tx_hash,
  mock_utxo_ref, mocktail_tx, tx_in,
}
use oracle_nft
use tests/utils.{mock_vault_oracle}
use types.{RBurn, RMint}

test s0_mint_success_mint() {
  let redeemer = RMint
  let input_utxo = mock_utxo_ref(0, 1)
  let policy_id = mock_vault_oracle

  let tx =
    mocktail_tx()
      |> mint(True, 1, policy_id, "")
      |> tx_in(True, mock_tx_hash(0), 1, zero, mock_pub_key_address(0, None))
      |> complete()

  oracle_nft.oracle_nft.mint(input_utxo, redeemer, policy_id, tx)
}

test s0_mint_fail_mint_no_utxo_ref_supply() {
  let redeemer = RMint
  let policy_id = mock_vault_oracle

  let tx =
    mocktail_tx()
      |> mint(True, 1, policy_id, "")
      |> tx_in(True, mock_tx_hash(0), 1, zero, mock_pub_key_address(0, None))
      |> complete()
  !oracle_nft.oracle_nft.mint(mock_utxo_ref(0, 0), redeemer, policy_id, tx)
}

test s0_mint_success_burn() {
  let redeemer = RBurn
  let policy_id = mock_vault_oracle

  let tx = Transaction { ..placeholder, mint: from_asset(policy_id, "", -1) }
  oracle_nft.oracle_nft.mint(mock_utxo_ref(0, 0), redeemer, policy_id, tx)
}

test s0_mint_success_burn_with_other_minting() {
  let redeemer = RBurn
  let policy_id = mock_vault_oracle

  let tx =
    Transaction {
      ..placeholder,
      mint: from_asset(policy_id, "", -1) |> add(mock_policy_id(999), "", 1),
    }
  oracle_nft.oracle_nft.mint(mock_utxo_ref(0, 0), redeemer, policy_id, tx)
}

test s0_mint_fail_burn_with_mint() {
  let redeemer = RBurn
  let policy_id = mock_vault_oracle

  let tx = Transaction { ..placeholder, mint: from_asset(policy_id, "", 1) }
  !oracle_nft.oracle_nft.mint(mock_utxo_ref(0, 0), redeemer, policy_id, tx)
}
