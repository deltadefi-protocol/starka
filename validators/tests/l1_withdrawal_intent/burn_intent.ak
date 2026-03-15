use aiken/cbor
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use l1_withdrawal_intent/spend_and_mint as l1_withdrawal_intent
use mocktail.{
  complete, mint, mock_pub_key_address, mock_tx_hash, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, required_signer_hash, tx_in, tx_in_inline_datum,
  tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_l1_withdrawal_intent_script_hash, mock_message, mock_operation_key,
  mock_operator_key, mock_signatures, mock_total_deposited, mock_total_shares,
  mock_vault_equity, mock_vault_nft, mock_vault_oracle_datum,
  mock_vault_script_hash, null_hash,
}
use types.{
  BurnIntent, SharesDelete, SharesRecordEntry, VaultOracleDatum,
  WithdrawalIntentDatum,
}
use withdraw_utils.{convert_shares_to_usd}

// ========== BurnIntent Tests ==========
// Spec:
// - Signed by operation_key from app_oracle OR operator_key from vault oracle
// - L1WithdrawalIntent is burnt with total batched amount
// - Vault Oracle input with datum (identified by vault_oracle_nft)
// - Vault Oracle output with updated datum:
//   - total_shares = total_shares - sum(shares_to_redeem) + sum(fee_shares)
//   - operator_shares += sum(fee_shares)
//   - total_deposited -= sum(cost_basis)
//   - shares_merkle_root updated
//   - total_fee_collected += sum(fee)
// - Vault unlocks net_payout to user
//
// TODO: These tests require a mock_message that includes vault_oracle_nft with price 0.
// The current mock_message only has ADA=2, USDM=1. The convert_value_to_usd function
// fails when the vault value contains the NFT without a corresponding price.
// Update mock_message and mock_signatures in tests/utils.ak to include the NFT price.
//
// Prices from mock_message: ADA=2, USDM=1 (TODO: add vault_oracle_nft=0)

// Test values:
// - shares_to_redeem = 1_250_000_000_000_000 (to get integer gross_value)
// - gross_value = shares_to_redeem * vault_equity / total_shares
//              = 1_250_000_000_000_000 * 2_400_000_000 / 3_000_000_000_000_000
//              = 1_000_000_000 USD
// - cost_basis = 1_000_000_000 (no profit, so fee = 0)
// - With operator_charge_percentage = 0, fee = 0 anyway
// - user_receives = gross_value = 1_000_000_000 USD
// - In ADA (price=2): 500_000_000 ADA

const mock_shares_to_redeem = 1_250_000_000_000_000

const mock_cost_basis = 1_000_000_000

fn mock_l1_withdrawal_datum() -> WithdrawalIntentDatum {
  WithdrawalIntentDatum {
    withdrawer: mock_pub_key_address(0, None),
    shares_to_redeem: mock_shares_to_redeem,
  }
}

fn computed_gross_value() -> Int {
  convert_shares_to_usd(mock_shares_to_redeem, mock_total_shares, mock_vault_equity)
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

type BurnIntentTestCase {
  is_vault_oracle_input_present: Bool,
  is_vault_oracle_output_correct: Bool,
  is_app_oracle_ref_present: Bool,
  is_vault_unlock_correct: Bool,
  is_intent_burn_correct: Bool,
  is_operation_signed: Bool,
  is_operator_signed: Bool,
}

fn mock_burn_intent_tx(test_case: BurnIntentTestCase) -> Transaction {
  let BurnIntentTestCase {
    is_vault_oracle_input_present,
    is_vault_oracle_output_correct,
    is_app_oracle_ref_present,
    is_vault_unlock_correct,
    is_intent_burn_correct,
    is_operation_signed,
    is_operator_signed,
  } = test_case

  let policy_id = mock_l1_withdrawal_intent_script_hash
  let withdrawer = mock_pub_key_address(0, None)
  let user_receives = computed_user_receives()

  // Vault Oracle + Vault combined (single UTxO holds both oracle datum and vault funds)
  // Located at vault_script_hash (where vault funds are), identified by vault_oracle_nft
  let vault_address = from_script(mock_vault_script_hash)
  let ada_to_unlock = user_receives / 2

  // The vault/oracle UTxO has: oracle NFT + actual vault funds
  // Starting with 1 billion ADA in the vault
  let vault_oracle_input_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 1_000_000_000)

  // After full withdrawal (SharesDelete), merkle root becomes empty
  let new_merkle_root = null_hash

  let vault_oracle_output_datum =
    build_vault_oracle_output_datum(new_merkle_root, is_vault_oracle_output_correct)

  // Vault output keeps remaining funds + oracle NFT
  let vault_oracle_output_value =
    if is_vault_unlock_correct {
      // Vault keeps (1_000_000_000 - 500_000_000) = 500_000_000 ADA + oracle NFT
      from_asset(mock_vault_nft, "", 1) |> add("", "", 1_000_000_000 - ada_to_unlock)
    } else {
      // Incorrect: vault keeps all
      from_asset(mock_vault_nft, "", 1) |> add("", "", 1_000_000_000)
    }

  // App Oracle reference input
  let app_oracle_ref_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  // Intent input (only has intent token + min ADA)
  let intent_input_value =
    from_asset("", "", 2_000_000) |> add(policy_id, "", 1)

  // Withdrawer receives the unlocked value
  let withdrawer_output_value =
    if is_vault_unlock_correct {
      from_asset("", "", ada_to_unlock)
    } else {
      from_asset("", "", 1_000_000)
    }

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
    // Vault Oracle + Vault combined input (single UTxO)
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
    |> tx_in_inline_datum(True, mock_l1_withdrawal_datum())
    // App Oracle reference input
    |> ref_tx_in(
        is_app_oracle_ref_present,
        mock_tx_hash(30),
        0,
        app_oracle_ref_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_ref_present, mock_app_oracle_datum)
    // Vault Oracle + Vault combined output
    |> tx_out(True, vault_address, vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_oracle_output_datum)
    // Withdrawer output (receives unlocked funds)
    |> tx_out(True, withdrawer, withdrawer_output_value)
    // Burn intent token
    |> mint(True, burn_amount, policy_id, "")
    // Signed by operation_key and/or operator_key
    |> required_signer_hash(is_operation_signed, mock_operation_key)
    |> required_signer_hash(is_operator_signed, mock_operator_key)
    |> complete()
}

fn build_redeemer() -> types.IntentRedeemer {
  let mpf_action = build_shares_delete_action()
  // Index 3 because: [0]=utxo_ref_input, [1]=vault_oracle_input, [2]=vault_input, [3]=intent_input
  // Output index 1 because: [0]=vault_oracle_output, [1]=withdrawer_output
  BurnIntent([1], mock_message, mock_signatures, [mpf_action])
}

// Success: All conditions met, signed by operation_key
test s3_mint_burn_intent_success() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
        is_operator_signed: False,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Success: Signed by operator_key instead of operation_key
test s3_mint_burn_intent_success_operator_signed() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: True,
        is_operation_signed: False,
        is_operator_signed: True,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Fail: Missing vault oracle input
test s3_mint_burn_intent_fail_no_vault_oracle_input() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: False,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
        is_operator_signed: False,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Fail: Incorrect vault oracle output datum
test s3_mint_burn_intent_fail_wrong_oracle_output() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: False,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
        is_operator_signed: False,
      },
    )

  !l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Fail: Missing app oracle reference input
test s3_mint_burn_intent_fail_no_app_oracle_ref() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: False,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
        is_operator_signed: False,
      },
    )

  l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Fail: Vault doesn't unlock correct amount to user
test s3_mint_burn_intent_fail_vault_unlock_mismatch() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: False,
        is_intent_burn_correct: True,
        is_operation_signed: True,
        is_operator_signed: False,
      },
    )

  !l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Fail: Incorrect intent burn count
test s3_mint_burn_intent_fail_wrong_burn_count() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: False,
        is_operation_signed: True,
        is_operator_signed: False,
      },
    )

  !l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}

// Fail: Not signed by either operation_key or operator_key
test s3_mint_burn_intent_fail_not_authorized() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_vault_unlock_correct: True,
        is_intent_burn_correct: True,
        is_operation_signed: False,
        is_operator_signed: False,
      },
    )

  !l1_withdrawal_intent.l1_withdrawal_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l1_withdrawal_intent_script_hash,
    tx,
  )
}
