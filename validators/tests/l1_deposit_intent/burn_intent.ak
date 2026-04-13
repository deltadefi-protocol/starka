// use aiken/cbor
// use aiken/merkle_patricia_forestry as mpf
// use cardano/address.{from_script}
// use cardano/assets.{add, from_asset, from_asset_list}
// use cardano/transaction.{Transaction}
// use deposit_utils.{cal_shares_amount}
// use l1_deposit_intent/spend_and_mint as l1_deposit_intent
// use mocktail.{
//   complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx, ref_tx_in,
//   ref_tx_in_inline_datum, required_signer_hash, tx_in, tx_in_inline_datum,
//   tx_out, tx_out_inline_datum,
// }
// use tests/utils.{
//   mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
//   mock_deposit_intent_datum, mock_deposit_m_value,
//   mock_l1_deposit_intent_script_hash, mock_message, mock_operation_key,
//   mock_operator_shares, mock_signatures, mock_total_deposited, mock_total_shares,
//   mock_user_account, mock_vault_equity, mock_vault_nft, mock_vault_oracle_datum,
//   mock_vault_script_hash,
// }
// use types.{
//   BurnIntent, IntentRedeemerL1, SharesInsert, SharesRecordEntry,
//   VaultOracleDatum,
// }

// // ========== BurnIntent Tests ==========
// // Spec:
// // - Signed by operation_key from app_oracle
// // - L1DepositIntent is burnt with total batched amount
// // - Vault Oracle input with datum (identified by vault_oracle_nft)
// // - Vault Oracle output with updated datum:
// //   - total_shares += sum(cal_shares)
// //   - total_deposited += sum(intent_usd_value)
// //   - shares_merkle_root updated
// // - Deposit value sent to vault
// //
// // NOTE on indices in BurnIntent redeemer:
// // The actual index values are NOT used in process_batched_deposit_intent_validation.
// // Only the LENGTH of indices matters - it acts as a counter to ensure the correct number
// // of deposit intent UTxOs are processed. The index values are discarded with `_output_index`.
// // See deposit_utils.ak: `[_output_index, ..rest_of_indices]`
// // This means [2], [0], [99] would all work the same for a single intent since length = 1.

// // Prices from mock_message: ADA=2, USDM=1 (used in price verification)

// // mock_deposit_m_value: 1749190790 ADA + 143533706 USDM
// // USD value = 1749190790 * 2 + 143533706 * 1 = 3641915286
// const deposit_usd_value = 3641915286

// fn computed_shares() -> Int {
//   cal_shares_amount(deposit_usd_value, mock_vault_equity, mock_total_shares)
// }

// fn build_vault_oracle_input_datum() -> VaultOracleDatum {
//   mock_vault_oracle_datum
// }

// fn build_vault_oracle_output_datum(
//   cal_shares: Int,
//   usd_value: Int,
//   new_merkle_root: ByteArray,
// ) -> VaultOracleDatum {
//   // Depositor is non-operator, so operator_shares_added = 0
//   // operator_shares = operator_shares + operator_shares_added
//   //                = 0 + 0 = 0
//   VaultOracleDatum {
//     ..mock_vault_oracle_datum,
//     total_shares: mock_total_shares + cal_shares,
//     operator_shares: mock_operator_shares,
//     total_deposited: mock_total_deposited + usd_value,
//     shares_merkle_root: new_merkle_root,
//   }
// }

// fn build_mpf_insert_action(_depositor_account, _cal_shares: Int, _usd_value: Int) {
//   // new_value is computed in deposit_utils, not passed in redeemer
//   SharesInsert { proof: [] }
// }

// fn compute_new_merkle_root(
//   depositor_account,
//   cal_shares: Int,
//   usd_value: Int,
// ) -> ByteArray {
//   // Use Account directly as MPF key
//   let mpf_key = cbor.serialise(depositor_account)
//   let entry =
//     SharesRecordEntry { shares: cal_shares, total_deposited: usd_value }
//   let mpf_value = cbor.serialise(entry)
//   mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))
// }

// type BurnIntentTestCase {
//   is_vault_oracle_input_present: Bool,
//   is_vault_oracle_output_correct: Bool,
//   is_app_oracle_ref_present: Bool,
//   is_deposit_sent_to_vault: Bool,
//   is_intent_burn_correct: Bool,
//   is_operation_signed: Bool,
// }

// fn mock_burn_intent_tx(test_case: BurnIntentTestCase) -> Transaction {
//   let BurnIntentTestCase {
//     is_vault_oracle_input_present,
//     is_vault_oracle_output_correct,
//     is_app_oracle_ref_present,
//     is_deposit_sent_to_vault,
//     is_intent_burn_correct,
//     is_operation_signed,
//   } = test_case

//   let policy_id = mock_l1_deposit_intent_script_hash
//   let depositor_account = mock_user_account
//   let cal_shares = computed_shares()
//   let new_merkle_root =
//     compute_new_merkle_root(depositor_account, cal_shares, deposit_usd_value)

//   // Vault Oracle values
//   let vault_oracle_address = from_script(mock_vault_nft)
//   let vault_oracle_input_value =
//     from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
//   let vault_oracle_output_value =
//     from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

//   let vault_oracle_output_datum =
//     if is_vault_oracle_output_correct {
//       build_vault_oracle_output_datum(
//         cal_shares,
//         deposit_usd_value,
//         new_merkle_root,
//       )
//     } else {
//       // Incorrect: don't update total_shares
//       mock_vault_oracle_datum
//     }

//   // App Oracle reference input
//   let app_oracle_ref_value =
//     from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

//   // Intent input
//   let intent_input_value =
//     from_asset_list(mock_deposit_m_value) |> add(policy_id, "", 1)

//   // Vault output (receives deposit)
//   let vault_address = from_script(mock_vault_script_hash)
//   let vault_output_value =
//     if is_deposit_sent_to_vault {
//       from_asset_list(mock_deposit_m_value)
//     } else {
//       from_asset("", "", 1_000_000)
//     }

//   // Burn amount
//   let burn_amount =
//     if is_intent_burn_correct {
//       -1
//     } else {
//       -2
//     }

//   mocktail_tx()
//     // Input matching utxo_ref in mock_message: mock_utxo_ref(0, 0)
//     |> tx_in(
//         True,
//         mock_tx_hash(0),
//         0,
//         from_asset("", "", 2_000_000),
//         mock_pub_key_address(99, None),
//       )
//     // Vault Oracle input
//     |> tx_in(
//         is_vault_oracle_input_present,
//         mock_tx_hash(10),
//         0,
//         vault_oracle_input_value,
//         vault_oracle_address,
//       )
//     |> tx_in_inline_datum(
//         is_vault_oracle_input_present,
//         build_vault_oracle_input_datum(),
//       )
//     // Intent input
//     |> tx_in(
//         True,
//         mock_tx_hash(20),
//         0,
//         intent_input_value,
//         from_script(policy_id),
//       )
//     |> tx_in_inline_datum(True, mock_deposit_intent_datum)
//     // App Oracle reference input
//     |> ref_tx_in(
//         is_app_oracle_ref_present,
//         mock_tx_hash(30),
//         0,
//         app_oracle_ref_value,
//         mock_app_oracle_address,
//       )
//     |> ref_tx_in_inline_datum(is_app_oracle_ref_present, mock_app_oracle_datum)
//     // Vault Oracle output
//     |> tx_out(True, vault_oracle_address, vault_oracle_output_value)
//     |> tx_out_inline_datum(True, vault_oracle_output_datum)
//     // Vault output (receives deposit)
//     |> tx_out(True, vault_address, vault_output_value)
//     // Burn intent token
//     |> mint(True, burn_amount, policy_id, "")
//     // Signed by operation_key
//     |> required_signer_hash(is_operation_signed, mock_operation_key)
//     |> complete()
// }

// fn build_redeemer() -> IntentRedeemerL1 {
//   let depositor_account = mock_user_account
//   let cal_shares = computed_shares()
//   let mpf_action =
//     build_mpf_insert_action(depositor_account, cal_shares, deposit_usd_value)
//   // Index 2 because: [0]=utxo_ref_input, [1]=vault_oracle_input, [2]=intent_input
//   BurnIntent([2], mock_message, mock_signatures, [mpf_action])
// }

// // Success: All conditions met
// test s2_mint_burn_intent_success() {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: True,
//         is_deposit_sent_to_vault: True,
//         is_intent_burn_correct: True,
//         is_operation_signed: True,
//       },
//     )

//   l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Missing vault oracle input
// test s2_mint_burn_intent_fail_no_vault_oracle_input() fail {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: False,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: True,
//         is_deposit_sent_to_vault: True,
//         is_intent_burn_correct: True,
//         is_operation_signed: True,
//       },
//     )

//   l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Incorrect vault oracle output datum
// test s2_mint_burn_intent_fail_wrong_oracle_output() {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: False,
//         is_app_oracle_ref_present: True,
//         is_deposit_sent_to_vault: True,
//         is_intent_burn_correct: True,
//         is_operation_signed: True,
//       },
//     )

//   !l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Missing app oracle reference input
// test s2_mint_burn_intent_fail_no_app_oracle_ref() fail {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: False,
//         is_deposit_sent_to_vault: True,
//         is_intent_burn_correct: True,
//         is_operation_signed: True,
//       },
//     )

//   l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Deposit not sent to vault
// test s2_mint_burn_intent_fail_deposit_not_sent() {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: True,
//         is_deposit_sent_to_vault: False,
//         is_intent_burn_correct: True,
//         is_operation_signed: True,
//       },
//     )

//   !l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Incorrect intent burn count
// test s2_mint_burn_intent_fail_wrong_burn_count() {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: True,
//         is_deposit_sent_to_vault: True,
//         is_intent_burn_correct: False,
//         is_operation_signed: True,
//       },
//     )

//   !l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Not signed by operation_key
// test s2_mint_burn_intent_fail_not_signed() {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: True,
//         is_deposit_sent_to_vault: True,
//         is_intent_burn_correct: True,
//         is_operation_signed: False,
//       },
//     )

//   !l1_deposit_intent.l1_deposit_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l1_deposit_intent_script_hash,
//     tx,
//   )
// }
