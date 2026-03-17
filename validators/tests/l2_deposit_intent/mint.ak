use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{Transaction}
use cocktail.{address_payment_key}
use l2_deposit_intent/spend_and_mint as l2_deposit_intent
use mocktail.{
  complete, mint, mock_policy_id, mock_pub_key_address, mock_tx_hash,
  mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, required_signer_hash,
  script_withdrawal, tx_in, tx_in_inline_datum, tx_out, tx_out_inline_datum,
  withdrawal_redeemer_value,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_dex_order_book_address, mock_dex_order_book_datum,
  mock_dex_order_book_token, mock_hydra_account_script_hash,
  mock_l2_deposit_intent_script_hash, mock_operation_key, mock_vault_nft,
  mock_vault_oracle_datum,
}
use types.{
  BurnIntentL2, CancelIntentL2, L2DepositIntentDatum, MValue, MintIntentL2,
  ProcessVaultDeposit, SharesInsert,
}

// Fake redeemer for ProcessVaultDeposit (actual validation happens in hydra_account)
fn mock_process_vault_deposit_redeemer() {
  ProcessVaultDeposit(#"", [], SharesInsert { proof: [] })
}

// ========== L2 MintIntent Tests ==========
// Spec:
// - Intent UTxO only contains the intent token (no deposit value)
// - Deposit amount > 0 (tokens stored in Account UTxO, not intent)
// - Different from L1: L1 requires deposit_value >= deposit_amount in datum

// Mock L2 deposit intent datum
const mock_l2_deposit_m_value: MValue =
  [
    Pair("", [Pair("", 1749190790)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 143533706)],
    ),
  ]

const mock_l2_deposit_intent_datum: L2DepositIntentDatum =
  L2DepositIntentDatum {
    depositor: mock_pub_key_address(0, None),
    deposit_amount: mock_l2_deposit_m_value,
  }

type MintIntentTestCase {
  is_token_minted_correctly: Bool,
  is_output_to_correct_address: Bool,
  is_deposit_amount_valid: Bool,
  is_depositor_signed: Bool,
}

fn mock_mint_intent_tx(test_case: MintIntentTestCase) -> Transaction {
  let MintIntentTestCase {
    is_token_minted_correctly,
    is_output_to_correct_address,
    is_deposit_amount_valid,
    is_depositor_signed,
  } = test_case

  let policy_id = mock_l2_deposit_intent_script_hash
  let wrong_policy_id = mock_policy_id(999)

  let output_address =
    if is_output_to_correct_address {
      from_script(policy_id)
    } else {
      from_script(wrong_policy_id)
    }

  let mint_amount =
    if is_token_minted_correctly {
      1
    } else {
      2
    }

  // L2 intent output only has intent token + min ADA (no deposit value)
  let output_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

  // Datum with deposit amount (or empty if testing invalid)
  let datum =
    if is_deposit_amount_valid {
      mock_l2_deposit_intent_datum
    } else {
      L2DepositIntentDatum {
        depositor: mock_pub_key_address(0, None),
        deposit_amount: [],
      }
    }

  // Depositor PKH from mock_pub_key_address(0, None)
  let depositor_pkh = address_payment_key(mock_pub_key_address(0, None))

  mocktail_tx()
    |> mint(True, mint_amount, policy_id, "")
    |> tx_out(True, output_address, output_value)
    |> tx_out_inline_datum(True, datum)
    |> required_signer_hash(is_depositor_signed, depositor_pkh)
    |> complete()
}

// Success: Mint intent with correct token, valid deposit amount, and depositor signature
test s4_mint_mint_intent_success() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_output_to_correct_address: True,
        is_deposit_amount_valid: True,
        is_depositor_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    MintIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Wrong mint amount (minted 2 instead of 1)
test s4_mint_mint_intent_fail_wrong_mint_amount() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: False,
        is_output_to_correct_address: True,
        is_deposit_amount_valid: True,
        is_depositor_signed: True,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    MintIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Output to wrong address (not script address)
test s4_mint_mint_intent_fail_wrong_output_address() fail {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_output_to_correct_address: False,
        is_deposit_amount_valid: True,
        is_depositor_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    MintIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Empty deposit amount in datum
test s4_mint_mint_intent_fail_empty_deposit_amount() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_output_to_correct_address: True,
        is_deposit_amount_valid: False,
        is_depositor_signed: True,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    MintIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Not signed by depositor
test s4_mint_mint_intent_fail_not_signed() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_output_to_correct_address: True,
        is_deposit_amount_valid: True,
        is_depositor_signed: False,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    MintIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// ========== L2 CancelIntent Tests ==========
// Spec:
// - L2DepositIntent token is burnt
// - Signed by operation_key from app_oracle (NOT depositor like L1)
// - Vault Oracle input required (to get app_oracle reference)
// - No value refund needed (tokens are in Account UTxO, not intent)

type CancelIntentTestCase {
  is_token_burnt_correctly: Bool,
  is_vault_oracle_present: Bool,
  is_app_oracle_ref_present: Bool,
  is_signed_by_operation_key: Bool,
}

fn mock_cancel_intent_tx(test_case: CancelIntentTestCase) -> Transaction {
  let CancelIntentTestCase {
    is_token_burnt_correctly,
    is_vault_oracle_present,
    is_app_oracle_ref_present,
    is_signed_by_operation_key,
  } = test_case

  let policy_id = mock_l2_deposit_intent_script_hash

  let burn_amount =
    if is_token_burnt_correctly {
      -1
    } else {
      -2
    }

  // L2 intent input only has intent token + min ADA
  let input_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

  // Vault Oracle values
  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  // App Oracle reference input
  let app_oracle_ref_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // Vault Oracle input (required to get app_oracle reference)
    |> tx_in(
        is_vault_oracle_present,
        mock_tx_hash(10),
        0,
        vault_oracle_value,
        vault_oracle_address,
      )
    |> tx_in_inline_datum(is_vault_oracle_present, mock_vault_oracle_datum)
    // L2 Intent input
    |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
    |> tx_in_inline_datum(True, mock_l2_deposit_intent_datum)
    // App Oracle reference input
    |> ref_tx_in(
        is_app_oracle_ref_present,
        mock_tx_hash(30),
        0,
        app_oracle_ref_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_ref_present, mock_app_oracle_datum)
    // Burn intent token
    |> mint(True, burn_amount, policy_id, "")
    // Signed by operation_key (not depositor like L1)
    |> required_signer_hash(is_signed_by_operation_key, mock_operation_key)
    |> complete()
}

// Success: Cancel intent with correct burn and operation_key signature
test s4_mint_cancel_intent_success() {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: True,
        is_signed_by_operation_key: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    CancelIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing vault oracle input
test s4_mint_cancel_intent_fail_no_vault_oracle() fail {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: False,
        is_app_oracle_ref_present: True,
        is_signed_by_operation_key: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    CancelIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing app oracle reference input
test s4_mint_cancel_intent_fail_no_app_oracle_ref() fail {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: False,
        is_signed_by_operation_key: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    CancelIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Not signed by operation_key
test s4_mint_cancel_intent_fail_not_signed() {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: True,
        is_signed_by_operation_key: False,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    CancelIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// ========== L2 BurnIntentL2 Tests ==========
// Spec:
// - Intent token is burnt (exactly 1)
// - Withdrawal script is validated (hydra_account ProcessVaultDeposit)
// - No batching in L2 (single intent per tx)

type BurnIntentTestCase {
  is_token_burnt_correctly: Bool,
  is_vault_oracle_present: Bool,
  is_app_oracle_ref_present: Bool,
  is_dex_order_book_ref_present: Bool,
  is_withdrawal_validated: Bool,
}

fn mock_burn_intent_tx(test_case: BurnIntentTestCase) -> Transaction {
  let BurnIntentTestCase {
    is_token_burnt_correctly,
    is_vault_oracle_present,
    is_app_oracle_ref_present,
    is_dex_order_book_ref_present,
    is_withdrawal_validated,
  } = test_case

  let policy_id = mock_l2_deposit_intent_script_hash

  let burn_amount =
    if is_token_burnt_correctly {
      -1
    } else {
      1
    }

  // L2 intent input only has intent token + min ADA
  let input_value = from_lovelace(2_000_000) |> add(policy_id, "", 1)

  // Vault Oracle values
  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  // App Oracle reference input
  let app_oracle_ref_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  // DexOrderBook reference input
  let dex_order_book_ref_value =
    from_asset(mock_dex_order_book_token, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    // Vault Oracle input (required to get app_oracle reference)
    |> tx_in(
        is_vault_oracle_present,
        mock_tx_hash(10),
        0,
        vault_oracle_value,
        vault_oracle_address,
      )
    |> tx_in_inline_datum(is_vault_oracle_present, mock_vault_oracle_datum)
    // L2 Intent input
    |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
    |> tx_in_inline_datum(True, mock_l2_deposit_intent_datum)
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
        mock_tx_hash(40),
        0,
        dex_order_book_ref_value,
        mock_dex_order_book_address,
      )
    |> ref_tx_in_inline_datum(
        is_dex_order_book_ref_present,
        mock_dex_order_book_datum,
      )
    // Burn intent token
    |> mint(True, burn_amount, policy_id, "")
    // Withdrawal script validated (hydra_account ProcessVaultDeposit)
    |> script_withdrawal(
        is_withdrawal_validated,
        mock_hydra_account_script_hash,
        0,
      )
    |> withdrawal_redeemer_value(
        is_withdrawal_validated,
        mock_process_vault_deposit_redeemer(),
      )
    |> complete()
}

// Success: Burn intent with withdrawal script validated
test s4_mint_burn_intent_success() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_withdrawal_validated: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    BurnIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Wrong burn amount
test s4_mint_burn_intent_fail_wrong_burn_amount() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_token_burnt_correctly: False,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_withdrawal_validated: True,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    BurnIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing withdrawal script validation
test s4_mint_burn_intent_fail_no_withdrawal_validated() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_withdrawal_validated: False,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    BurnIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing vault oracle input
test s4_mint_burn_intent_fail_no_vault_oracle() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: False,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_withdrawal_validated: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    BurnIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing dex order book reference
test s4_mint_burn_intent_fail_no_dex_order_book() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_token_burnt_correctly: True,
        is_vault_oracle_present: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: False,
        is_withdrawal_validated: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    BurnIntentL2,
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}
