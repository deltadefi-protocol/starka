use aiken/cbor
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use mocktail.{
  complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx,
  required_signer_hash, tx_in, tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_deposit_m_value, mock_initial_utxo, mock_message, mock_operator_key,
  mock_signatures, mock_vault_nft, null_hash,
}
use types.{CloseVault, CreateVault, LPRecordEntry, VaultDatum}
use vault/spend_mint as vault

// ========== CreateVault ==========

const mock_initial_lp = 3641915286

fn mock_create_vault_datum() -> VaultDatum {
  let operator_address = from_verification_key(mock_operator_key)
  let mpf_key = cbor.serialise(operator_address)
  let entry = LPRecordEntry { lp: mock_initial_lp, cost: mock_initial_lp }
  let mpf_value = cbor.serialise(entry)
  let computed_root = mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))

  VaultDatum {
    app_oracle: mock_app_oracle,
    l1_deposit_intent_script_hash: #"",
    l1_withdrawal_intent_script_hash: #"",
    l2_deposit_intent_script_hash: #"",
    l2_withdrawal_intent_script_hash: #"",
    pluggable_logic: #"",
    vault_stake_rotation_script_hash: #"",
    operator_key: mock_operator_key,
    operator_charge_percentage: 0,
    operator_min_deposit_percentage: 10,
    hydra_node_pub_keys: [
      #"8a2447b9e7f1705aa5b2dcb16a7254db089fbac7e462cf6008e9a6dc8a7a6c21",
      #"312803d57366263f9e5310262fb9984f58dbc5602ad5ebdd5725719f4f913ced",
      #"fa357c31b2e47f49d4e0da6eac605a4dc068f4e72fbc56bfef2850e2da1ba3a3",
    ],
    total_lp: mock_initial_lp,
    operator_lp: mock_initial_lp,
    vault_cost: mock_initial_lp,
    lp_merkle_root: computed_root,
    is_active: True,
  }
}

fn mock_create_vault_tx() -> Transaction {
  let vault_datum = mock_create_vault_datum()
  let vault_nft_policy = mock_vault_nft

  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)
  let vault_output_value =
    from_asset_list(mock_deposit_m_value)
      |> add(vault_nft_policy, "", 1)

  mocktail_tx()
    // Initial UTxO consumed (one-shot)
    |> tx_in(
        True,
        mock_tx_hash(99),
        0,
        from_asset("", "", 2_000_000),
        mock_pub_key_address(0, None),
      )
    // Input matching utxo_ref in mock_message: mock_utxo_ref(0, 0)
    |> tx_in(
        True,
        mock_tx_hash(0),
        0,
        from_asset("", "", 2_000_000),
        mock_pub_key_address(0, None),
      )
    // App oracle input (spending)
    |> tx_in(
        True,
        mock_tx_hash(1),
        0,
        app_oracle_value,
        mock_app_oracle_address,
      )
    |> tx_in_inline_datum(True, mock_app_oracle_datum)
    // App oracle output (unchanged)
    |> tx_out(True, mock_app_oracle_address, app_oracle_value)
    |> tx_out_inline_datum(True, mock_app_oracle_datum)
    // Vault output
    |> tx_out(True, from_script(vault_nft_policy), vault_output_value)
    |> tx_out_inline_datum(True, vault_datum)
    // Mint vault NFT
    |> mint(True, 1, vault_nft_policy, "")
    // Operator signature
    |> required_signer_hash(True, mock_operator_key)
    |> complete()
}

test test_create_vault_success() {
  let redeemer =
    CreateVault {
      initial_deposit: mock_deposit_m_value,
      initial_lp: mock_initial_lp,
      prices_message: mock_message,
      signatures: mock_signatures,
      initial_lp_proof: [],
    }
  let tx = mock_create_vault_tx()
  vault.vault.mint(
    mock_initial_utxo,
    mock_app_oracle,
    redeemer,
    mock_vault_nft,
    tx,
  )
}

// ========== CloseVault ==========

fn mock_close_vault_tx() -> Transaction {
  let vault_nft_policy = mock_vault_nft
  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  let close_vault_datum =
    VaultDatum {
      app_oracle: mock_app_oracle,
      l1_deposit_intent_script_hash: #"",
      l1_withdrawal_intent_script_hash: #"",
      l2_deposit_intent_script_hash: #"",
      l2_withdrawal_intent_script_hash: #"",
      pluggable_logic: #"",
      vault_stake_rotation_script_hash: #"",
      operator_key: mock_operator_key,
      operator_charge_percentage: 0,
      operator_min_deposit_percentage: 10,
      hydra_node_pub_keys: [
        #"8a2447b9e7f1705aa5b2dcb16a7254db089fbac7e462cf6008e9a6dc8a7a6c21",
        #"312803d57366263f9e5310262fb9984f58dbc5602ad5ebdd5725719f4f913ced",
        #"fa357c31b2e47f49d4e0da6eac605a4dc068f4e72fbc56bfef2850e2da1ba3a3",
      ],
      total_lp: 0,
      operator_lp: 0,
      vault_cost: 0,
      lp_merkle_root: null_hash,
      is_active: True,
    }

  let vault_input_value =
    from_asset(vault_nft_policy, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // App oracle input
    |> tx_in(
        True,
        mock_tx_hash(1),
        0,
        app_oracle_value,
        mock_app_oracle_address,
      )
    |> tx_in_inline_datum(True, mock_app_oracle_datum)
    // Vault input
    |> tx_in(
        True,
        mock_tx_hash(2),
        0,
        vault_input_value,
        from_script(vault_nft_policy),
      )
    |> tx_in_inline_datum(True, close_vault_datum)
    // App oracle output
    |> tx_out(True, mock_app_oracle_address, app_oracle_value)
    |> tx_out_inline_datum(True, mock_app_oracle_datum)
    // Burn vault NFT
    |> mint(True, -1, vault_nft_policy, "")
    // Operator signature
    |> required_signer_hash(True, mock_operator_key)
    |> complete()
}

test test_close_vault_success() {
  let tx = mock_close_vault_tx()
  vault.vault.mint(
    mock_initial_utxo,
    mock_app_oracle,
    CloseVault,
    mock_vault_nft,
    tx,
  )
}
