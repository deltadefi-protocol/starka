use aiken/cbor
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use deposit_utils.{cal_lp_amount}
use l1_deposit_intent/spend_and_mint as l1_deposit_intent
use mocktail.{
  complete, mint, mock_pub_key_address, mock_pub_key_hash, mock_tx_hash,
  mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, required_signer_hash, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use price_oracle_utils.{convert_m_value_to_usd}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_deposit_intent_datum, mock_deposit_m_value,
  mock_l1_deposit_intent_script_hash, mock_message, mock_node_pub_keys,
  mock_operator_key, mock_signatures, mock_total_lp, mock_vault_cost,
  mock_vault_nft, null_hash,
}
use types.{
  BurnIntent, CancelIntent, DepositIntentDatum, LPInsert, LPRecordEntry,
  MintIntent, VaultDatum,
}

// ========== MintIntent ==========

test test_mint_intent_success() {
  let policy_id = mock_l1_deposit_intent_script_hash
  let output_value =
    from_asset_list(mock_deposit_m_value)
      |> add(policy_id, "", 1)
  let tx =
    mocktail_tx()
      |> mint(True, 1, policy_id, "")
      |> tx_out(True, from_script(policy_id), output_value)
      |> tx_out_inline_datum(True, mock_deposit_intent_datum)
      |> complete()

  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    MintIntent,
    policy_id,
    tx,
  )
}

// ========== BurnIntent ==========

// Prices from mock_message: ADA=2, USDM=1
const prices =
  [
    Pair(
      (
        #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
        #"5553444d",
      ),
      1,
    ),
    Pair(("", ""), 2),
  ]

// mock_deposit_m_value: 1749190790 ADA + 143533706 USDM
// USD value = 1749190790 * 2 + 143533706 * 1 = 3641915286
const deposit_usd_value = 3641915286

// vault_balance from mock_message = 2400000000
const mock_vault_balance = 2400000000

fn computed_lp() -> Int {
  cal_lp_amount(deposit_usd_value, mock_vault_balance, mock_total_lp)
}

fn build_vault_input_datum() -> VaultDatum {
  VaultDatum {
    app_oracle: mock_app_oracle,
    l1_deposit_intent_script_hash: mock_l1_deposit_intent_script_hash,
    l1_withdrawal_intent_script_hash: #"",
    l2_deposit_intent_script_hash: #"",
    l2_withdrawal_intent_script_hash: #"",
    pluggable_logic: #"",
    vault_stake_rotation_script_hash: #"",
    operator_key: mock_operator_key,
    operator_charge_percentage: 0,
    operator_min_deposit_percentage: 10,
    hydra_node_pub_keys: mock_node_pub_keys,
    total_lp: mock_total_lp,
    operator_lp: 0,
    vault_cost: mock_vault_cost,
    lp_merkle_root: null_hash,
    is_active: True,
  }
}

test test_burn_intent_success() {
  let policy_id = mock_l1_deposit_intent_script_hash
  let vault_input_datum = build_vault_input_datum()

  // Compute expected LP and new merkle root
  let cal_lp = computed_lp()
  let lp_address = mock_pub_key_address(0, None)
  let mpf_key = cbor.serialise(lp_address)
  let new_entry = LPRecordEntry { lp: cal_lp, cost: deposit_usd_value }
  let mpf_value = cbor.serialise(new_entry)
  let new_root = mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))

  let vault_output_datum =
    VaultDatum {
      ..vault_input_datum,
      total_lp: mock_total_lp + cal_lp,
      vault_cost: mock_vault_cost + deposit_usd_value,
      lp_merkle_root: new_root,
    }

  // Vault values
  let vault_address = from_script(mock_vault_nft)
  let vault_input_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let vault_output_value =
    from_asset_list(mock_deposit_m_value)
      |> add(mock_vault_nft, "", 1)
      |> add("", "", 2_000_000)

  // Intent input
  let intent_input_value =
    from_asset_list(mock_deposit_m_value)
      |> add(policy_id, "", 1)

  // App oracle
  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  let mpf_action =
    LPInsert { proof: [], new_value: mpf_value }

  let tx =
    mocktail_tx()
      // Input matching utxo_ref in mock_message: mock_utxo_ref(0, 0)
      |> tx_in(
          True,
          mock_tx_hash(0),
          0,
          from_asset("", "", 2_000_000),
          mock_pub_key_address(0, None),
        )
      // Vault input
      |> tx_in(True, mock_tx_hash(10), 0, vault_input_value, vault_address)
      |> tx_in_inline_datum(True, vault_input_datum)
      // Intent input
      |> tx_in(
          True,
          mock_tx_hash(20),
          0,
          intent_input_value,
          from_script(policy_id),
        )
      |> tx_in_inline_datum(True, mock_deposit_intent_datum)
      // App oracle reference input
      |> ref_tx_in(
          True,
          mock_tx_hash(30),
          0,
          app_oracle_value,
          mock_app_oracle_address,
        )
      |> ref_tx_in_inline_datum(True, mock_app_oracle_datum)
      // Vault output
      |> tx_out(True, vault_address, vault_output_value)
      |> tx_out_inline_datum(True, vault_output_datum)
      // Burn intent token
      |> mint(True, -1, policy_id, "")
      |> complete()

  let redeemer =
    BurnIntent([0], mock_message, mock_signatures, [mpf_action])

  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    redeemer,
    policy_id,
    tx,
  )
}

// ========== CancelIntent ==========

test test_cancel_intent_success() {
  let policy_id = mock_l1_deposit_intent_script_hash
  let intent_value =
    from_asset_list(mock_deposit_m_value)
      |> add(policy_id, "", 1)
  let depositor_pkh = mock_pub_key_hash(0)

  let tx =
    mocktail_tx()
      |> tx_in(True, mock_tx_hash(0), 0, intent_value, from_script(policy_id))
      |> tx_in_inline_datum(True, mock_deposit_intent_datum)
      |> mint(True, -1, policy_id, "")
      |> required_signer_hash(True, depositor_pkh)
      |> complete()

  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    CancelIntent,
    policy_id,
    tx,
  )
}
