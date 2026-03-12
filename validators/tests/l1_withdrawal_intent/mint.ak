use aiken/cbor
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use l1_withdrawal_intent/spend_and_mint as l1_withdrawal_intent
use mocktail.{
  complete, mint, mock_pub_key_address, mock_pub_key_hash, mock_tx_hash,
  mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, required_signer_hash, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_l1_withdrawal_intent_script_hash, mock_message, mock_node_pub_keys,
  mock_operator_key, mock_signatures, mock_vault_nft,
  mock_withdrawal_intent_datum, null_hash, usdm_name, usdm_policy,
}
use types.{
  BurnIntent, CancelIntent, LPDelete, LPRecordEntry, MintIntent, VaultDatum,
  WithdrawalIntentDatum,
}

// ========== MintIntent ==========

test test_mint_intent_success() {
  let policy_id = mock_l1_withdrawal_intent_script_hash
  let output_value =
    from_asset(policy_id, "", 1) |> add("", "", 2_000_000)
  let tx =
    mocktail_tx()
      |> mint(True, 1, policy_id, "")
      |> tx_out(True, from_script(policy_id), output_value)
      |> tx_out_inline_datum(True, mock_withdrawal_intent_datum)
      |> complete()

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    MintIntent,
    policy_id,
    tx,
  )
}

// ========== BurnIntent ==========

// Single full withdrawal, operator_charge_percentage=0, no operator fee action.
// Use usdm_policy as vault_nft so convert_value_to_usd works
// (vault value only contains priced assets).

const user_lp = 1_000_000

const user_cost = 800_000

// vault_balance from mock_message = 2400000000
// gross_value = user_lp * vault_balance / total_lp = 1000000 * 2400000000 / 1000000 = 2400000000
const user_receives = 2400000000

fn build_withdrawal_vault_datum(merkle_root: ByteArray) -> VaultDatum {
  VaultDatum {
    app_oracle: mock_app_oracle,
    l1_deposit_intent_script_hash: #"",
    l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
    l2_deposit_intent_script_hash: #"",
    l2_withdrawal_intent_script_hash: #"",
    pluggable_logic: #"",
    vault_stake_rotation_script_hash: #"",
    operator_key: mock_operator_key,
    operator_charge_percentage: 0,
    operator_min_deposit_percentage: 10,
    hydra_node_pub_keys: mock_node_pub_keys,
    total_lp: user_lp,
    operator_lp: 0,
    vault_cost: user_cost,
    lp_merkle_root: merkle_root,
    is_active: True,
  }
}

test test_burn_intent_success() {
  let policy_id = mock_l1_withdrawal_intent_script_hash
  // Use usdm_policy as vault_nft for this test so vault value has only priced assets
  let test_vault_nft = usdm_policy

  // Compute initial merkle root with single user entry
  let lp_address = mock_pub_key_address(0, None)
  let mpf_key = cbor.serialise(lp_address)
  let old_entry = LPRecordEntry { lp: user_lp, cost: user_cost }
  let old_value = cbor.serialise(old_entry)
  let initial_root = mpf.root(mpf.insert(mpf.empty, mpf_key, old_value, []))

  let vault_input_datum = build_withdrawal_vault_datum(initial_root)
  let vault_output_datum =
    VaultDatum {
      ..vault_input_datum,
      total_lp: 0,
      operator_lp: 0,
      vault_cost: 0,
      lp_merkle_root: null_hash,
    }

  let vault_address = from_script(test_vault_nft)
  // Vault value in USDM only (price=1), so convert_value_to_usd works
  let vault_input_value =
    from_asset(usdm_policy, usdm_name, 2_500_000_000)
  let vault_output_value =
    from_asset(usdm_policy, usdm_name, 100_000_000)

  // User output: receives 2400000000 USD as USDM
  let user_output_value =
    from_asset(usdm_policy, usdm_name, user_receives)

  // Intent input
  let intent_datum =
    WithdrawalIntentDatum {
      lp_address: lp_address,
      amount: user_lp,
    }
  let intent_input_value =
    from_asset(policy_id, "", 1) |> add("", "", 2_000_000)

  // App oracle reference
  let app_oracle_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  let mpf_action = LPDelete { proof: [], old_value: old_value }

  // outputs[0] = vault, outputs[1] = user
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
      |> tx_in_inline_datum(True, intent_datum)
      // App oracle reference
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
      // User output (index 1)
      |> tx_out(True, lp_address, user_output_value)
      // Burn intent token
      |> mint(True, -1, policy_id, "")
      |> complete()

  let redeemer =
    BurnIntent([1], mock_message, mock_signatures, [mpf_action])

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    test_vault_nft,
    redeemer,
    policy_id,
    tx,
  )
}

// ========== CancelIntent ==========

test test_cancel_intent_success() {
  let policy_id = mock_l1_withdrawal_intent_script_hash
  let intent_value =
    from_asset(policy_id, "", 1) |> add("", "", 2_000_000)
  let withdrawer_pkh = mock_pub_key_hash(0)

  let tx =
    mocktail_tx()
      |> tx_in(True, mock_tx_hash(0), 0, intent_value, from_script(policy_id))
      |> tx_in_inline_datum(True, mock_withdrawal_intent_datum)
      |> mint(True, -1, policy_id, "")
      |> required_signer_hash(True, withdrawer_pkh)
      |> complete()

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    CancelIntent,
    policy_id,
    tx,
  )
}
