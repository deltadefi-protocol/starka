// use aiken/cbor
// use aiken/merkle_patricia_forestry as mpf
// use cardano/address.{from_script}
// use cardano/assets.{add, from_asset}
// use cardano/transaction.{Transaction}
// use l1_withdrawal_intent/spend_and_mint as l1_withdrawal_intent
// use mocktail.{
//   complete, mint, mock_pub_key_address, mock_pub_key_hash, mock_tx_hash,
//   mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, required_signer_hash, tx_in,
//   tx_in_inline_datum, tx_out, tx_out_inline_datum,
// }
// use tests/utils.{
//   mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
//   mock_l1_withdrawal_intent_script_hash, mock_message, mock_node_pub_keys,
//   mock_operator_key, mock_signatures, mock_vault_nft, mock_vault_script_hash,
//   mock_withdrawal_intent_datum, null_hash, usdm_name, usdm_policy,
// }
// use types.{
//   BurnIntent, CancelIntent, SharesDelete, SharesRecordEntry, MintIntent, VaultOracleDatum,
//   WithdrawalIntentDatum,
// }

// // ========== MintIntent ==========

// test test_mint_intent_success() {
//   let policy_id = mock_l1_withdrawal_intent_script_hash
//   let output_value =
//     from_asset(policy_id, "", 1) |> add("", "", 2_000_000)
//   let tx =
//     mocktail_tx()
//       |> mint(True, 1, policy_id, "")
//       |> tx_out(True, from_script(policy_id), output_value)
//       |> tx_out_inline_datum(True, mock_withdrawal_intent_datum)
//       |> complete()

//   l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     MintIntent,
//     policy_id,
//     tx,
//   )
// }

// // ========== BurnIntent ==========

// // Single full withdrawal, operator_charge_percentage=0, no operator fee action.
// // Use usdm_policy as vault_nft so convert_value_to_usd works
// // (vault value only contains priced assets).

// const user_shares = 1_000_000

// const user_total_deposited = 800_000

// // vault_equity from mock_message = 2400000000
// // gross_value = user_shares * vault_equity / total_shares = 1000000 * 2400000000 / 1000000 = 2400000000
// const user_receives = 2400000000

// fn build_withdrawal_vault_datum(merkle_root: ByteArray) -> VaultOracleDatum {
//   VaultOracleDatum {
//     app_oracle: mock_app_oracle,
//     vault_script_hash: mock_vault_script_hash,
//     l1_deposit_intent_script_hash: #"",
//     l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
//     l2_deposit_intent_script_hash: #"",
//     l2_withdrawal_intent_script_hash: #"",
//     pluggable_logic: #"",
//     vault_stake_rotation_script_hash: #"",
//     operator_key: mock_operator_key,
//     operator_charge_percentage: 0,
//     operator_min_deposit_percentage: 10,
//     hydra_node_pub_keys: mock_node_pub_keys,
//     is_active: True,
//     total_shares: user_shares,
//     operator_shares: 0,
//     total_deposited: user_total_deposited,
//     shares_merkle_root: merkle_root,
//     total_fee_collected: 0,
//   }
// }

// test test_burn_intent_success() {
//   let policy_id = mock_l1_withdrawal_intent_script_hash
//   // Use usdm_policy as vault_nft for this test so vault value has only priced assets
//   let test_vault_nft = usdm_policy

//   // Compute initial merkle root with single user entry
//   let withdrawer = mock_pub_key_address(0, None)
//   let mpf_key = cbor.serialise(withdrawer)
//   let old_entry = SharesRecordEntry { shares: user_shares, total_deposited: user_total_deposited }
//   let old_value = cbor.serialise(old_entry)
//   let initial_root = mpf.root(mpf.insert(mpf.empty, mpf_key, old_value, []))

//   let vault_input_datum = build_withdrawal_vault_datum(initial_root)
//   let vault_output_datum =
//     VaultOracleDatum {
//       ..vault_input_datum,
//       total_shares: 0,
//       operator_shares: 0,
//       total_deposited: 0,
//       shares_merkle_root: null_hash,
//     }

//   let vault_address = from_script(test_vault_nft)
//   // Vault value in USDM only (price=1), so convert_value_to_usd works
//   let vault_input_value =
//     from_asset(usdm_policy, usdm_name, 2_500_000_000)
//   let vault_output_value =
//     from_asset(usdm_policy, usdm_name, 100_000_000)

//   // User output: receives 2400000000 USD as USDM
//   let user_output_value =
//     from_asset(usdm_policy, usdm_name, user_receives)

//   // Intent input
//   let intent_datum =
//     WithdrawalIntentDatum {
//       withdrawer: withdrawer,
//       shares_to_redeem: user_shares,
//     }
//   let intent_input_value =
//     from_asset(policy_id, "", 1) |> add("", "", 2_000_000)

//   // App oracle reference
//   let app_oracle_value =
//     from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

//   let mpf_action = SharesDelete { proof: [], old_value: old_value }

//   // outputs[0] = vault, outputs[1] = user
//   let tx =
//     mocktail_tx()
//       // Input matching utxo_ref in mock_message: mock_utxo_ref(0, 0)
//       |> tx_in(
//           True,
//           mock_tx_hash(0),
//           0,
//           from_asset("", "", 2_000_000),
//           mock_pub_key_address(0, None),
//         )
//       // Vault input
//       |> tx_in(True, mock_tx_hash(10), 0, vault_input_value, vault_address)
//       |> tx_in_inline_datum(True, vault_input_datum)
//       // Intent input
//       |> tx_in(
//           True,
//           mock_tx_hash(20),
//           0,
//           intent_input_value,
//           from_script(policy_id),
//         )
//       |> tx_in_inline_datum(True, intent_datum)
//       // App oracle reference
//       |> ref_tx_in(
//           True,
//           mock_tx_hash(30),
//           0,
//           app_oracle_value,
//           mock_app_oracle_address,
//         )
//       |> ref_tx_in_inline_datum(True, mock_app_oracle_datum)
//       // Vault output
//       |> tx_out(True, vault_address, vault_output_value)
//       |> tx_out_inline_datum(True, vault_output_datum)
//       // User output (index 1)
//       |> tx_out(True, withdrawer, user_output_value)
//       // Burn intent token
//       |> mint(True, -1, policy_id, "")
//       |> complete()

//   let redeemer =
//     BurnIntent([1], mock_message, mock_signatures, [mpf_action])

//   l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     test_vault_nft,
//     redeemer,
//     policy_id,
//     tx,
//   )
// }

// // ========== CancelIntent ==========

// test test_cancel_intent_success() {
//   let policy_id = mock_l1_withdrawal_intent_script_hash
//   let intent_value =
//     from_asset(policy_id, "", 1) |> add("", "", 2_000_000)
//   let withdrawer_pkh = mock_pub_key_hash(0)

//   let tx =
//     mocktail_tx()
//       |> tx_in(True, mock_tx_hash(0), 0, intent_value, from_script(policy_id))
//       |> tx_in_inline_datum(True, mock_withdrawal_intent_datum)
//       |> mint(True, -1, policy_id, "")
//       |> required_signer_hash(True, withdrawer_pkh)
//       |> complete()

//   l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     CancelIntent,
//     policy_id,
//     tx,
//   )
// }
