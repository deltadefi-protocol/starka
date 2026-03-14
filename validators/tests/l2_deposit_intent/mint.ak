// use aiken/cbor
// use aiken/merkle_patricia_forestry as mpf
// use cardano/address.{from_script}
// use cardano/assets.{add, from_asset, from_asset_list}
// use cardano/transaction.{Transaction}
// use deposit_utils.{cal_shares_amount}
// use l2_deposit_intent/spend_and_mint as l2_deposit_intent
// use mocktail.{
//   complete, mint, mock_pub_key_address, mock_pub_key_hash, mock_tx_hash,
//   mocktail_tx, required_signer_hash, tx_in, tx_in_inline_datum, tx_out,
//   tx_out_inline_datum,
// }
// use tests/utils.{
//   mock_app_oracle, mock_deposit_intent_datum, mock_deposit_m_value,
//   mock_l2_deposit_intent_script_hash, mock_message, mock_node_pub_keys,
//   mock_operator_key, mock_signatures, mock_total_shares, mock_total_deposited,
//   mock_vault_nft, mock_vault_script_hash, null_hash,
// }
// use types.{
//   BurnIntent, CancelIntent, SharesInsert, SharesRecordEntry, MintIntent, VaultOracleDatum,
// }

// // ========== MintIntent ==========

// test test_mint_intent_success() {
//   let policy_id = mock_l2_deposit_intent_script_hash
//   let output_value =
//     from_asset_list(mock_deposit_m_value)
//       |> add(policy_id, "", 1)
//   let tx =
//     mocktail_tx()
//       |> mint(True, 1, policy_id, "")
//       |> tx_out(True, from_script(policy_id), output_value)
//       |> tx_out_inline_datum(True, mock_deposit_intent_datum)
//       |> complete()

//   l2_deposit_intent.l2_deposit_intent.mint(
//     mock_vault_nft,
//     MintIntent,
//     policy_id,
//     tx,
//   )
// }

// // ========== BurnIntent ==========

// // Same prices and calculations as L1, but no app_oracle reference input.
// // L2 derives hydra_signers from vault_datum.hydra_node_pub_keys directly.

// const deposit_usd_value = 3641915286

// const mock_vault_equity = 2400000000

// fn computed_shares() -> Int {
//   cal_shares_amount(deposit_usd_value, mock_vault_equity, mock_total_shares)
// }

// fn build_vault_input_datum() -> VaultOracleDatum {
//   VaultOracleDatum {
//     app_oracle: mock_app_oracle,
//     vault_script_hash: mock_vault_script_hash,
//     l1_deposit_intent_script_hash: #"",
//     l1_withdrawal_intent_script_hash: #"",
//     l2_deposit_intent_script_hash: mock_l2_deposit_intent_script_hash,
//     l2_withdrawal_intent_script_hash: #"",
//     pluggable_logic: #"",
//     vault_stake_rotation_script_hash: #"",
//     operator_key: mock_operator_key,
//     operator_charge_percentage: 0,
//     operator_min_deposit_percentage: 10,
//     hydra_node_pub_keys: mock_node_pub_keys,
//     is_active: True,
//     total_shares: mock_total_shares,
//     operator_shares: 0,
//     total_deposited: mock_total_deposited,
//     shares_merkle_root: null_hash,
//     total_fee_collected: 0,
//   }
// }

// test test_burn_intent_success() {
//   let policy_id = mock_l2_deposit_intent_script_hash
//   let vault_input_datum = build_vault_input_datum()

//   let cal_shares = computed_shares()
//   let depositor = mock_pub_key_address(0, None)
//   let mpf_key = cbor.serialise(depositor)
//   let new_entry = SharesRecordEntry { shares: cal_shares, total_deposited: deposit_usd_value }
//   let mpf_value = cbor.serialise(new_entry)
//   let new_root = mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))

//   let vault_output_datum =
//     VaultOracleDatum {
//       ..vault_input_datum,
//       total_shares: mock_total_shares + cal_shares,
//       total_deposited: mock_total_deposited + deposit_usd_value,
//       shares_merkle_root: new_root,
//     }

//   let vault_address = from_script(mock_vault_nft)
//   let vault_input_value =
//     from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
//   let vault_output_value =
//     from_asset_list(mock_deposit_m_value)
//       |> add(mock_vault_nft, "", 1)
//       |> add("", "", 2_000_000)

//   let intent_input_value =
//     from_asset_list(mock_deposit_m_value)
//       |> add(policy_id, "", 1)

//   let mpf_action = SharesInsert { proof: [], new_value: mpf_value }

//   // No app_oracle reference input for L2
//   let tx =
//     mocktail_tx()
//       |> tx_in(
//           True,
//           mock_tx_hash(0),
//           0,
//           from_asset("", "", 2_000_000),
//           mock_pub_key_address(0, None),
//         )
//       |> tx_in(True, mock_tx_hash(10), 0, vault_input_value, vault_address)
//       |> tx_in_inline_datum(True, vault_input_datum)
//       |> tx_in(
//           True,
//           mock_tx_hash(20),
//           0,
//           intent_input_value,
//           from_script(policy_id),
//         )
//       |> tx_in_inline_datum(True, mock_deposit_intent_datum)
//       |> tx_out(True, vault_address, vault_output_value)
//       |> tx_out_inline_datum(True, vault_output_datum)
//       |> mint(True, -1, policy_id, "")
//       |> complete()

//   let redeemer =
//     BurnIntent([0], mock_message, mock_signatures, [mpf_action])

//   l2_deposit_intent.l2_deposit_intent.mint(
//     mock_vault_nft,
//     redeemer,
//     policy_id,
//     tx,
//   )
// }

// // ========== CancelIntent ==========

// test test_cancel_intent_success() {
//   let policy_id = mock_l2_deposit_intent_script_hash
//   let intent_value =
//     from_asset_list(mock_deposit_m_value)
//       |> add(policy_id, "", 1)
//   let depositor_pkh = mock_pub_key_hash(0)

//   let tx =
//     mocktail_tx()
//       |> tx_in(True, mock_tx_hash(0), 0, intent_value, from_script(policy_id))
//       |> tx_in_inline_datum(True, mock_deposit_intent_datum)
//       |> mint(True, -1, policy_id, "")
//       |> required_signer_hash(True, depositor_pkh)
//       |> complete()

//   l2_deposit_intent.l2_deposit_intent.mint(
//     mock_vault_nft,
//     CancelIntent,
//     policy_id,
//     tx,
//   )
// }
