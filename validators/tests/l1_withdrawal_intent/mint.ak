// use cardano/address.{from_script}
// use cardano/assets.{add, from_lovelace}
// use cardano/transaction.{Transaction}
// use l1_withdrawal_intent/spend_and_mint as l1_withdrawal_intent
// use mocktail.{
//   complete, mint, mock_policy_id, mock_pub_key_hash, mock_tx_hash, mocktail_tx,
//   required_signer_hash, tx_in, tx_in_inline_datum, tx_out, tx_out_inline_datum,
// }
// use tests/utils.{
//   mock_l1_withdrawal_intent_script_hash, mock_user_trade_account, mock_vault_nft,
// }
// use types.{CancelIntent, MintIntent, WithdrawalIntentDatum}

// // ========== MintIntent Tests ==========
// // Spec:
// // - Withdrawal amount > 0 (shares_to_redeem > 0)
// // - No vault reference needed (user creates intent independently)

// const mock_l1_withdrawal_intent_datum: WithdrawalIntentDatum =
//   WithdrawalIntentDatum {
//     withdrawer: mock_user_trade_account,
//     shares_to_redeem: 1_000_000,
//   }

// type MintIntentTestCase {
//   is_token_minted_correctly: Bool,
//   is_output_to_correct_address: Bool,
//   is_shares_valid: Bool,
// }

// fn mock_mint_intent_tx(test_case: MintIntentTestCase) -> Transaction {
//   let MintIntentTestCase {
//     is_token_minted_correctly,
//     is_output_to_correct_address,
//     is_shares_valid,
//   } = test_case

//   let policy_id = mock_l1_withdrawal_intent_script_hash
//   let wrong_policy_id = mock_policy_id(999)

//   let output_address =
//     if is_output_to_correct_address {
//       from_script(policy_id)
//     } else {
//       from_script(wrong_policy_id)
//     }

//   let mint_amount =
//     if is_token_minted_correctly {
//       1
//     } else {
//       2
//     }

//   // Intent output has min ADA + intent token
//   let output_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

//   // Datum with shares amount (or 0 if testing invalid)
//   let datum =
//     if is_shares_valid {
//       mock_l1_withdrawal_intent_datum
//     } else {
//       WithdrawalIntentDatum {
//         withdrawer: mock_user_trade_account,
//         shares_to_redeem: 0,
//       }
//     }

//   mocktail_tx()
//     |> mint(True, mint_amount, policy_id, "")
//     |> tx_out(True, output_address, output_value)
//     |> tx_out_inline_datum(True, datum)
//     |> complete()
// }

// // Success: Mint intent with correct token and valid shares amount
// test s3_mint_mint_intent_success() {
//   let tx =
//     mock_mint_intent_tx(
//       MintIntentTestCase {
//         is_token_minted_correctly: True,
//         is_output_to_correct_address: True,
//         is_shares_valid: True,
//       },
//     )

//   l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     MintIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Wrong mint amount (minted 2 instead of 1)
// test s3_mint_mint_intent_fail_wrong_mint_amount() {
//   let tx =
//     mock_mint_intent_tx(
//       MintIntentTestCase {
//         is_token_minted_correctly: False,
//         is_output_to_correct_address: True,
//         is_shares_valid: True,
//       },
//     )

//   !l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     MintIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Output to wrong address (not script address)
// test s3_mint_mint_intent_fail_wrong_output_address() fail {
//   let tx =
//     mock_mint_intent_tx(
//       MintIntentTestCase {
//         is_token_minted_correctly: True,
//         is_output_to_correct_address: False,
//         is_shares_valid: True,
//       },
//     )

//   l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     MintIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Zero shares_to_redeem
// test s3_mint_mint_intent_fail_zero_shares() {
//   let tx =
//     mock_mint_intent_tx(
//       MintIntentTestCase {
//         is_token_minted_correctly: True,
//         is_output_to_correct_address: True,
//         is_shares_valid: False,
//       },
//     )

//   !l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     MintIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// // ========== CancelIntent Tests ==========
// // Spec:
// // - L1WithdrawalIntent token is burnt
// // - The intent UTxO value returned to withdrawer (refund)
// // - Signed by the withdrawer
// // - No vault interaction required

// type CancelIntentTestCase {
//   is_token_burnt_correctly: Bool,
//   is_signed_by_withdrawer: Bool,
// }

// fn mock_cancel_intent_tx(test_case: CancelIntentTestCase) -> Transaction {
//   let CancelIntentTestCase { is_token_burnt_correctly, is_signed_by_withdrawer } =
//     test_case

//   let policy_id = mock_l1_withdrawal_intent_script_hash
//   let withdrawer_pkh = mock_pub_key_hash(0)
//   let wrong_pkh = mock_pub_key_hash(999)

//   let burn_amount =
//     if is_token_burnt_correctly {
//       -1
//     } else {
//       -2
//     }

//   let signer_pkh =
//     if is_signed_by_withdrawer {
//       withdrawer_pkh
//     } else {
//       wrong_pkh
//     }

//   let input_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

//   mocktail_tx()
//     |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
//     |> tx_in_inline_datum(True, mock_l1_withdrawal_intent_datum)
//     |> mint(True, burn_amount, policy_id, "")
//     |> required_signer_hash(True, signer_pkh)
//     |> complete()
// }

// // Success: Cancel intent with correct burn and signature
// test s3_mint_cancel_intent_success() {
//   let tx =
//     mock_cancel_intent_tx(
//       CancelIntentTestCase {
//         is_token_burnt_correctly: True,
//         is_signed_by_withdrawer: True,
//       },
//     )

//   l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     CancelIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Wrong burn amount (burnt 2 instead of 1)
// test s3_mint_cancel_intent_fail_wrong_burn_amount() {
//   let tx =
//     mock_cancel_intent_tx(
//       CancelIntentTestCase {
//         is_token_burnt_correctly: False,
//         is_signed_by_withdrawer: True,
//       },
//     )

//   !l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     CancelIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// // Fail: Not signed by withdrawer
// test s3_mint_cancel_intent_fail_not_signed_by_withdrawer() {
//   let tx =
//     mock_cancel_intent_tx(
//       CancelIntentTestCase {
//         is_token_burnt_correctly: True,
//         is_signed_by_withdrawer: False,
//       },
//     )

//   !l1_withdrawal_intent.l1_withdrawal_intent.mint(
//     mock_vault_nft,
//     CancelIntent,
//     mock_l1_withdrawal_intent_script_hash,
//     tx,
//   )
// }
