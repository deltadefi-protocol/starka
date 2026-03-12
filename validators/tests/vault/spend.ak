use cardano/assets.{add, from_asset}
use cardano/transaction.{Mint, Transaction}
use mocktail.{
  add_redeemer, complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx,
  required_signer_hash, script_withdrawal, tx_in, tx_in_inline_datum, tx_out,
  tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_hydra_signer_1, mock_hydra_signer_2, mock_hydra_signer_3,
  mock_initial_utxo, mock_l1_deposit_intent_script_hash,
  mock_l1_withdrawal_intent_script_hash, mock_l2_deposit_intent_script_hash,
  mock_l2_withdrawal_intent_script_hash, mock_operator_key, mock_pluggable_logic,
  mock_vault_address, mock_vault_datum, mock_vault_nft,
}
use types.{
  BurnIntent, HydraCommit, HydraDecommit, PluggableLogic, ProcessL1Deposit,
  ProcessL1Withdrawal, ProcessL2Deposit, ProcessL2Withdrawal, Trade,
}
use vault/spend_mint as vault

// ========== ProcessL1Deposit ==========

fn mock_process_intent_tx(intent_script_hash: ByteArray) -> Transaction {
  let burn_redeemer: Data = BurnIntent([0], "", [], [])
  mocktail_tx()
    |> mint(True, -1, intent_script_hash, "")
    |> complete()
    |> add_redeemer(True, Pair(Mint(intent_script_hash), burn_redeemer))
}

test test_process_l1_deposit_success() {
  let tx = mock_process_intent_tx(mock_l1_deposit_intent_script_hash)
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    ProcessL1Deposit,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== ProcessL1Withdrawal ==========

test test_process_l1_withdrawal_success() {
  let tx = mock_process_intent_tx(mock_l1_withdrawal_intent_script_hash)
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    ProcessL1Withdrawal,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== ProcessL2Deposit ==========

test test_process_l2_deposit_success() {
  let tx = mock_process_intent_tx(mock_l2_deposit_intent_script_hash)
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    ProcessL2Deposit,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== ProcessL2Withdrawal ==========

test test_process_l2_withdrawal_success() {
  let tx = mock_process_intent_tx(mock_l2_withdrawal_intent_script_hash)
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    ProcessL2Withdrawal,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== HydraCommit ==========

fn mock_hydra_tx() -> Transaction {
  let vault_value = from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, vault_value, mock_vault_address)
    |> tx_in_inline_datum(True, mock_vault_datum)
    |> tx_out(True, mock_vault_address, vault_value)
    |> tx_out_inline_datum(True, mock_vault_datum)
    |> required_signer_hash(True, mock_hydra_signer_1)
    |> required_signer_hash(True, mock_hydra_signer_2)
    |> required_signer_hash(True, mock_hydra_signer_3)
    |> complete()
}

test test_hydra_commit_success() {
  let tx = mock_hydra_tx()
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    HydraCommit,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== HydraDecommit ==========

test test_hydra_decommit_success() {
  let tx = mock_hydra_tx()
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    HydraDecommit,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== Trade ==========

test test_trade_success() {
  let vault_value_in =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 5_000_000)
  let vault_value_out =
    from_asset(mock_vault_nft, "", 1)
      |> add("", "", 3_000_000)
      |> add(
          #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
          #"5553444d",
          2_000_000,
        )
  let tx =
    mocktail_tx()
      |> tx_in(True, mock_tx_hash(0), 0, vault_value_in, mock_vault_address)
      |> tx_in_inline_datum(True, mock_vault_datum)
      |> tx_out(True, mock_vault_address, vault_value_out)
      |> tx_out_inline_datum(True, mock_vault_datum)
      |> required_signer_hash(True, mock_operator_key)
      |> complete()
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    Trade,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== PluggableLogic ==========

test test_pluggable_logic_success() {
  let tx =
    mocktail_tx()
      |> script_withdrawal(True, mock_pluggable_logic, 0)
      |> complete()
  vault.vault.spend(
    mock_initial_utxo,
    mock_app_oracle,
    Some(mock_vault_datum),
    PluggableLogic,
    mock_utxo_ref(0, 0),
    tx,
  )
}
