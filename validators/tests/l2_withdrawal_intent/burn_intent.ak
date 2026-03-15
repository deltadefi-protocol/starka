use aiken/cbor
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{Transaction}
use l2_withdrawal_intent/spend_and_mint as l2_withdrawal_intent
use mocktail.{
  complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, required_signer_hash, tx_in, tx_in_inline_datum,
  tx_out, tx_out_inline_datum,
}
use tests/utils.{
  build_dex_order_book_datum, mock_app_oracle, mock_app_oracle_address,
  mock_app_oracle_datum, mock_dex_order_book_address, mock_dex_order_book_token,
  mock_l2_withdrawal_intent_script_hash, mock_message, mock_operation_key,
  mock_operator_key, mock_signatures, mock_total_deposited, mock_total_shares,
  mock_vault_equity, mock_vault_nft, mock_vault_oracle_datum,
  mock_vault_script_hash, null_hash,
}
use types.{
  BurnIntent, L2WithdrawalIntentDatum, MValue, SharesDelete, SharesRecordEntry,
  VaultOracleDatum,
}
use withdraw_utils.{convert_shares_to_usd}

// ========== BurnIntent Tests ==========
// Spec:
// - Signed by operation_key from app_oracle OR operator_key from vault oracle
// - L2WithdrawalIntent is burnt with total batched amount
// - Vault Oracle input/output with updated datum
// - Balance transferred via TransferIntent (net_payout == transfer amount_l2 in USD)
// - App Oracle and DexOrderBook reference inputs required
//
// TODO: These tests require:
// 1. A mock_message that includes vault_oracle_nft with price 0
// 2. Proper TransferIntent setup with hydra_user_intent inputs
// The current mock_message only has ADA=2, USDM=1.
// Update mock_message and mock_signatures in tests/utils.ak to include required prices.
//
// Prices from mock_message: ADA=2, USDM=1 (TODO: add vault_oracle_nft=0)

// Test values (same as L1 withdrawal):
// - shares_to_redeem = 1_250_000_000_000_000 (to get integer gross_value)
// - gross_value = shares_to_redeem * vault_equity / total_shares = 1_000_000_000 USD
// - cost_basis = 1_000_000_000 (no profit, so fee = 0)
// - user_receives = gross_value = 1_000_000_000 USD

const mock_shares_to_redeem = 1_250_000_000_000_000

const mock_cost_basis = 1_000_000_000

fn mock_l2_withdrawal_datum() -> L2WithdrawalIntentDatum {
  L2WithdrawalIntentDatum {
    withdrawer: mock_pub_key_address(0, None),
    shares_to_redeem: mock_shares_to_redeem,
  }
}

fn computed_gross_value() -> Int {
  convert_shares_to_usd(
    mock_shares_to_redeem,
    mock_total_shares,
    mock_vault_equity,
  )
}

fn computed_user_receives() -> Int {
  // fee = 0 since operator_charge_percentage = 0
  computed_gross_value()
}

// Build initial merkle root with withdrawer's shares
fn build_initial_merkle_root() -> ByteArray {
  let withdrawer = mock_pub_key_address(0, None)
  let mpf_key = cbor.serialise(withdrawer)
  let entry =
    SharesRecordEntry {
      shares: mock_shares_to_redeem,
      total_deposited: mock_cost_basis,
    }
  let mpf_value = cbor.serialise(entry)
  mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))
}

fn build_vault_oracle_input_datum() -> VaultOracleDatum {
  VaultOracleDatum {
    ..mock_vault_oracle_datum,
    shares_merkle_root: build_initial_merkle_root(),
  }
}

fn build_vault_oracle_output_datum(
  new_merkle_root: ByteArray,
  is_correct: Bool,
) -> VaultOracleDatum {
  if is_correct {
    VaultOracleDatum {
      ..mock_vault_oracle_datum,
      total_shares: mock_total_shares - mock_shares_to_redeem,
      total_deposited: mock_total_deposited - mock_cost_basis,
      shares_merkle_root: new_merkle_root,
    }
  } else {
    // Incorrect: don't update total_shares
    mock_vault_oracle_datum
  }
}

fn build_shares_delete_action() -> types.SharesMPFAction {
  let entry =
    SharesRecordEntry {
      shares: mock_shares_to_redeem,
      total_deposited: mock_cost_basis,
    }
  let mpf_value = cbor.serialise(entry)
  SharesDelete { proof: [], old_value: mpf_value }
}

// Mock transfer amount (what user receives via TransferIntent)
// user_receives = 1_000_000_000 USD, with ADA price=2, that's 500_000_000 ADA
fn mock_transfer_amount() -> MValue {
  let ada_amount = computed_user_receives() / 2
  [Pair("", [Pair("", ada_amount)])]
}

type BurnIntentTestCase {
  is_vault_oracle_input_present: Bool,
  is_vault_oracle_output_correct: Bool,
  is_app_oracle_ref_present: Bool,
  is_dex_order_book_ref_present: Bool,
  is_transfer_intent_present: Bool,
  is_intent_burn_correct: Bool,
  is_operation_signed: Bool,
  is_operator_signed: Bool,
}

fn mock_burn_intent_tx(test_case: BurnIntentTestCase) -> Transaction {
  let BurnIntentTestCase {
    is_vault_oracle_input_present,
    is_vault_oracle_output_correct,
    is_app_oracle_ref_present,
    is_dex_order_book_ref_present,
    is_transfer_intent_present,
    is_intent_burn_correct,
    is_operation_signed,
    is_operator_signed,
  } = test_case

  let policy_id = mock_l2_withdrawal_intent_script_hash

  // Vault Oracle values (combined vault + oracle in single UTxO at vault_script_hash)
  let vault_address = from_script(mock_vault_script_hash)
  let vault_oracle_input_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  // After full withdrawal (SharesDelete), merkle root becomes empty
  let new_merkle_root = null_hash

  let vault_oracle_output_datum =
    build_vault_oracle_output_datum(
      new_merkle_root,
      is_vault_oracle_output_correct,
    )

  let vault_oracle_output_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  // App Oracle reference input
  let app_oracle_ref_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  // DexOrderBook reference input
  let dex_order_book_ref_value =
    from_asset(mock_dex_order_book_token, "", 1) |> add("", "", 2_000_000)

  // Intent input (only has intent token + min ADA)
  let intent_input_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

  // TransferIntent input (hydra_user_intent with transfer amount)
  // TODO: This needs proper HydraUserIntentDatum with TransferIntent
  // For now, we use a placeholder - actual test requires full hydra types
  let transfer_intent_value = from_lovelace(2_000_000)

  // Burn amount
  let burn_amount =
    if is_intent_burn_correct {
      -1
    } else {
      -2
    }

  mocktail_tx()
    // Input matching utxo_ref in mock_message: mock_utxo_ref(0, 0)
    |> tx_in(
        True,
        mock_tx_hash(0),
        0,
        from_asset("", "", 2_000_000),
        mock_pub_key_address(99, None),
      )
    // Vault Oracle input
    |> tx_in(
        is_vault_oracle_input_present,
        mock_tx_hash(10),
        0,
        vault_oracle_input_value,
        vault_address,
      )
    |> tx_in_inline_datum(
        is_vault_oracle_input_present,
        build_vault_oracle_input_datum(),
      )
    // Intent input
    |> tx_in(
        True,
        mock_tx_hash(20),
        0,
        intent_input_value,
        from_script(policy_id),
      )
    |> tx_in_inline_datum(True, mock_l2_withdrawal_datum())
    // TODO: TransferIntent input needs proper HydraUserIntentDatum
    // |> tx_in(is_transfer_intent_present, mock_tx_hash(25), 0, transfer_intent_value, from_script(hydra_user_intent_script_hash))
    // |> tx_in_inline_datum(is_transfer_intent_present, transfer_intent_datum)
    // App Oracle reference input
    |> ref_tx_in(
        is_app_oracle_ref_present,
        mock_tx_hash(30),
        0,
        app_oracle_ref_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_ref_present, mock_app_oracle_datum)
    // DexOrderBook reference input
    |> ref_tx_in(
        is_dex_order_book_ref_present,
        mock_tx_hash(35),
        0,
        dex_order_book_ref_value,
        mock_dex_order_book_address,
      )
    |> ref_tx_in_inline_datum(
        is_dex_order_book_ref_present,
        build_dex_order_book_datum(),
      )
    // Vault Oracle output
    |> tx_out(True, vault_address, vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_oracle_output_datum)
    // Burn intent token
    |> mint(True, burn_amount, policy_id, "")
    // Signed by operation_key and/or operator_key
    |> required_signer_hash(is_operation_signed, mock_operation_key)
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> complete()
}

fn build_redeemer() -> types.IntentRedeemer {
  let mpf_action = build_shares_delete_action()
  // Index for withdrawer output (not used in L2 since TransferIntent handles payout)
  BurnIntent([0], mock_message, mock_signatures, [mpf_action])
}
// TODO: BurnIntent tests require additional setup:
// 1. mock_message with vault_oracle_nft price
// 2. Proper TransferIntent inputs with HydraUserIntentDatum
// 3. DexOrderBook datum with hydra_user_intent_script_hash
//
// The tests below document the expected test structure but will fail until
// the above dependencies are resolved.

// Success: All conditions met, signed by operation_key
// test s5_mint_burn_intent_success() {
//   let tx =
//     mock_burn_intent_tx(
//       BurnIntentTestCase {
//         is_vault_oracle_input_present: True,
//         is_vault_oracle_output_correct: True,
//         is_app_oracle_ref_present: True,
//         is_dex_order_book_ref_present: True,
//         is_transfer_intent_present: True,
//         is_intent_burn_correct: True,
//         is_operation_signed: True,
//         is_operator_signed: False,
//       },
//     )
//
//   l2_withdrawal_intent.l2_withdrawal_intent.mint(
//     mock_vault_nft,
//     build_redeemer(),
//     mock_l2_withdrawal_intent_script_hash,
//     tx,
//   )
// }

// Success: Signed by operator_key instead of operation_key
// test s5_mint_burn_intent_success_operator_signed() { ... }

// Fail: Missing vault oracle input
// test s5_mint_burn_intent_fail_no_vault_oracle_input() fail { ... }

// Fail: Incorrect vault oracle output datum
// test s5_mint_burn_intent_fail_wrong_oracle_output() { ... }

// Fail: Missing app oracle reference input
// test s5_mint_burn_intent_fail_no_app_oracle_ref() fail { ... }

// Fail: Missing dex order book reference input
// test s5_mint_burn_intent_fail_no_dex_order_book_ref() fail { ... }

// Fail: Transfer amount mismatch (net_payout != transfer amount_l2)
// test s5_mint_burn_intent_fail_transfer_amount_mismatch() { ... }

// Fail: Incorrect intent burn count
// test s5_mint_burn_intent_fail_wrong_burn_count() { ... }

// Fail: Not signed by either operation_key or operator_key
// test s5_mint_burn_intent_fail_not_authorized() { ... }
