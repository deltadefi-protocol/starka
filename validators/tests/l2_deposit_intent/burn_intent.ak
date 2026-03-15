use aiken/cbor
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{Transaction}
use deposit_utils.{cal_shares_amount}
use hydra_dex/types.{
  Account, DexOrderBookDatum, HydraAccountIntent, HydraUserIntentDatum,
  MasterIntent, TransferIntent, UserTradeAccount,
} as dd_types
use l2_deposit_intent/spend_and_mint as l2_deposit_intent
use mocktail.{
  complete, mint, mock_pub_key_address, mock_script_hash, mock_tx_hash,
  mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, required_signer_hash, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_dex_account_balance_address, mock_dex_account_balance_token,
  mock_dex_order_book_address, mock_dex_order_book_token,
  mock_l2_deposit_intent_script_hash, mock_message, mock_operation_key,
  mock_signatures, mock_total_deposited, mock_total_shares, mock_vault_equity,
  mock_vault_nft, mock_vault_oracle_datum, null_hash,
}
use types.{
  BurnIntent, L2DepositIntentDatum, MValue, SharesInsert, SharesRecordEntry,
  VaultOracleDatum,
}

// ========== L2 BurnIntent Tests ==========
// Spec (L2 specific):
// - Signed by operation_key from app_oracle
// - L2DepositIntent is burnt with total batched amount
// - Vault Oracle input with datum (identified by vault_oracle_nft)
// - Vault Oracle output with updated datum:
//   - total_shares += sum(cal_shares)
//   - total_deposited += sum(intent_usd_value)
//   - shares_merkle_root updated
// - Balance transferred from user's Account UTxO to vault (via TransferIntent)
// - Each deposit intent's deposit_amount must equal the corresponding TransferIntent's amount_l2 (in USD value)
// - Verify prices message using hydra_node_pub_keys from Oracle datum
//
// NOTE on indices in BurnIntent redeemer:
// In L2, index values are IGNORED — only the list LENGTH matters for counting intent UTxOs.
// Transfer amounts are matched in order with intent UTxOs as they're processed.
// See deposit_utils.ak: `[_output_index, ..rest_of_indices]`
// This means [0], [99], [123] would all work the same for a single intent since length = 1.

// ========== Mock hydra user intent script hash ==========

const mock_hydra_user_intent_script_hash = mock_script_hash(50)

// ========== Mock DexOrderBookDatum ==========

fn build_dex_order_book_datum() -> DexOrderBookDatum {
  DexOrderBookDatum {
    operation_key: mock_operation_key,
    stop_key: mock_operation_key,
    fee_account: UserTradeAccount {
      account: Account {
        account_id: "fee_account",
        master_key: from_script(mock_hydra_user_intent_script_hash).payment_credential,
        operation_key: from_script(mock_hydra_user_intent_script_hash).payment_credential,
      },
      trading_logic: mock_hydra_user_intent_script_hash,
    },
    limit_orders_merkle_root: null_hash,
    dex_account_balance_token: mock_dex_account_balance_token,
    dex_account_balance_address: mock_dex_account_balance_address,
    dex_order_book_token: mock_dex_order_book_token,
    dex_order_book_address: mock_dex_order_book_address,
    hydra_user_intent_script_hash: mock_hydra_user_intent_script_hash,
    hydra_account_script_hash: mock_hydra_user_intent_script_hash,
    hydra_order_book_script_hash: mock_hydra_user_intent_script_hash,
    hydra_token_policy_id: mock_dex_order_book_token,
  }
}

// ========== Mock deposit values ==========
// Using simple values for predictable USD calculation
// Prices from mock_message: ADA=2, USDM=1
// mock_deposit_m_value: 1749190790 ADA + 143533706 USDM
// USD value = 1749190790 * 2 + 143533706 * 1 = 3641915286

const deposit_usd_value = 3641915286

const mock_l2_deposit_m_value: MValue =
  [
    Pair("", [Pair("", 1749190790)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 143533706)],
    ),
  ]

fn computed_shares() -> Int {
  cal_shares_amount(deposit_usd_value, mock_vault_equity, mock_total_shares)
}

// ========== Mock L2 deposit intent datum ==========

const mock_l2_deposit_intent_datum: L2DepositIntentDatum =
  L2DepositIntentDatum {
    depositor: mock_pub_key_address(0, None),
    deposit_amount: mock_l2_deposit_m_value,
  }

// ========== Mock TransferIntent input ==========
// TransferIntent is wrapped in MasterIntent -> HydraUserIntentDatum

fn build_transfer_intent_datum() -> HydraUserIntentDatum {
  let vault_account =
    UserTradeAccount {
      account: Account {
        account_id: "vault_account",
        master_key: from_script(mock_vault_nft).payment_credential,
        operation_key: from_script(mock_vault_nft).payment_credential,
      },
      trading_logic: mock_vault_nft,
    }

  let user_account =
    UserTradeAccount {
      account: Account {
        account_id: "user_account",
        master_key: mock_pub_key_address(0, None).payment_credential,
        operation_key: mock_pub_key_address(0, None).payment_credential,
      },
      trading_logic: mock_hydra_user_intent_script_hash,
    }

  let transfer_intent: HydraAccountIntent =
    TransferIntent { to: vault_account, amount_l2: mock_l2_deposit_m_value }

  let intent_data: Data = transfer_intent
  MasterIntent { account: user_account, intent: intent_data }
}

fn build_mismatched_transfer_intent_datum() -> HydraUserIntentDatum {
  // Transfer a different amount than deposit_amount
  let mismatched_amount: MValue = [Pair("", [Pair("", 1000000)])]

  // Much smaller than deposit_amount
  let vault_account =
    UserTradeAccount {
      account: Account {
        account_id: "vault_account",
        master_key: from_script(mock_vault_nft).payment_credential,
        operation_key: from_script(mock_vault_nft).payment_credential,
      },
      trading_logic: mock_vault_nft,
    }

  let user_account =
    UserTradeAccount {
      account: Account {
        account_id: "user_account",
        master_key: mock_pub_key_address(0, None).payment_credential,
        operation_key: mock_pub_key_address(0, None).payment_credential,
      },
      trading_logic: mock_hydra_user_intent_script_hash,
    }

  let transfer_intent: HydraAccountIntent =
    TransferIntent { to: vault_account, amount_l2: mismatched_amount }

  let intent_data: Data = transfer_intent
  MasterIntent { account: user_account, intent: intent_data }
}

// ========== Helper functions ==========

fn build_vault_oracle_output_datum(
  cal_shares: Int,
  usd_value: Int,
  new_merkle_root: ByteArray,
) -> VaultOracleDatum {
  VaultOracleDatum {
    ..mock_vault_oracle_datum,
    total_shares: mock_total_shares + cal_shares,
    total_deposited: mock_total_deposited + usd_value,
    shares_merkle_root: new_merkle_root,
  }
}

fn build_mpf_insert_action(_depositor_address, cal_shares: Int, usd_value: Int) {
  let entry =
    SharesRecordEntry { shares: cal_shares, total_deposited: usd_value }
  let mpf_value = cbor.serialise(entry)
  SharesInsert { proof: [], new_value: mpf_value }
}

fn compute_new_merkle_root(
  depositor_address,
  cal_shares: Int,
  usd_value: Int,
) -> ByteArray {
  let mpf_key = cbor.serialise(depositor_address)
  let entry =
    SharesRecordEntry { shares: cal_shares, total_deposited: usd_value }
  let mpf_value = cbor.serialise(entry)
  mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))
}

// ========== Test case config ==========

type BurnIntentTestCase {
  is_vault_oracle_input_present: Bool,
  is_vault_oracle_output_correct: Bool,
  is_app_oracle_ref_present: Bool,
  is_dex_order_book_ref_present: Bool,
  is_transfer_intent_present: Bool,
  is_transfer_amount_matching: Bool,
  is_intent_burn_correct: Bool,
  is_operation_signed: Bool,
}

fn mock_burn_intent_tx(test_case: BurnIntentTestCase) -> Transaction {
  let BurnIntentTestCase {
    is_vault_oracle_input_present,
    is_vault_oracle_output_correct,
    is_app_oracle_ref_present,
    is_dex_order_book_ref_present,
    is_transfer_intent_present,
    is_transfer_amount_matching,
    is_intent_burn_correct,
    is_operation_signed,
  } = test_case

  let policy_id = mock_l2_deposit_intent_script_hash
  let depositor = mock_pub_key_address(0, None)
  let cal_shares = computed_shares()
  let new_merkle_root =
    compute_new_merkle_root(depositor, cal_shares, deposit_usd_value)

  // Vault Oracle values
  let vault_oracle_address = from_script(mock_vault_nft)
  let vault_oracle_input_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)
  let vault_oracle_output_value =
    from_asset(mock_vault_nft, "", 1) |> add("", "", 2_000_000)

  let vault_oracle_output_datum =
    if is_vault_oracle_output_correct {
      build_vault_oracle_output_datum(
        cal_shares,
        deposit_usd_value,
        new_merkle_root,
      )
    } else {
      // Incorrect: don't update total_shares
      mock_vault_oracle_datum
    }

  // App Oracle reference input
  let app_oracle_ref_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  // DexOrderBook reference input
  let dex_order_book_ref_value =
    from_asset(mock_dex_order_book_token, "", 1) |> add("", "", 2_000_000)

  // L2 Intent input (only has intent token, no deposit value)
  let intent_input_value =
    from_asset(policy_id, "", 1) |> add("", "", 2_000_000)

  // TransferIntent input (from hydra_user_intent script)
  let transfer_intent_value =
    from_asset(mock_hydra_user_intent_script_hash, "", 1)
      |> add("", "", 2_000_000)

  let transfer_intent_datum =
    if is_transfer_amount_matching {
      build_transfer_intent_datum()
    } else {
      build_mismatched_transfer_intent_datum()
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
        from_lovelace(2_000_000),
        mock_pub_key_address(99, None),
      )
    // Vault Oracle input
    |> tx_in(
        is_vault_oracle_input_present,
        mock_tx_hash(10),
        0,
        vault_oracle_input_value,
        vault_oracle_address,
      )
    |> tx_in_inline_datum(
        is_vault_oracle_input_present,
        mock_vault_oracle_datum,
      )
    // L2 Intent input (only intent token)
    |> tx_in(
        True,
        mock_tx_hash(20),
        0,
        intent_input_value,
        from_script(policy_id),
      )
    |> tx_in_inline_datum(True, mock_l2_deposit_intent_datum)
    // TransferIntent input (from hydra_user_intent script)
    |> tx_in(
        is_transfer_intent_present,
        mock_tx_hash(25),
        0,
        transfer_intent_value,
        from_script(mock_hydra_user_intent_script_hash),
      )
    |> tx_in_inline_datum(is_transfer_intent_present, transfer_intent_datum)
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
    |> tx_out(True, vault_oracle_address, vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_oracle_output_datum)
    // Burn intent token
    |> mint(True, burn_amount, policy_id, "")
    // Signed by operation_key
    |> required_signer_hash(is_operation_signed, mock_operation_key)
    |> complete()
}

fn build_redeemer() -> types.IntentRedeemer {
  let depositor = mock_pub_key_address(0, None)
  let cal_shares = computed_shares()
  let mpf_action =
    build_mpf_insert_action(depositor, cal_shares, deposit_usd_value)
  // Index value is ignored in L2 (only length matters), using 0
  BurnIntent([0], mock_message, mock_signatures, [mpf_action])
}

// ========== Tests ==========

// Success: All conditions met
test s2_mint_burn_intent_success() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing vault oracle input
test s2_mint_burn_intent_fail_no_vault_oracle_input() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: False,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Incorrect vault oracle output datum
test s2_mint_burn_intent_fail_wrong_oracle_output() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: False,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing app oracle reference input
test s2_mint_burn_intent_fail_no_app_oracle_ref() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: False,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing DexOrderBook reference input
test s2_mint_burn_intent_fail_no_dex_order_book_ref() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: False,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Missing TransferIntent input
test s2_mint_burn_intent_fail_no_transfer_intent() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: False,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Transfer amount does not match deposit amount (in USD value)
// This is the key L2 security check
test s2_mint_burn_intent_fail_transfer_amount_mismatch() fail {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: False,
        is_intent_burn_correct: True,
        is_operation_signed: True,
      },
    )

  l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Incorrect intent burn count
test s2_mint_burn_intent_fail_wrong_burn_count() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: False,
        is_operation_signed: True,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Not signed by operation_key
test s2_mint_burn_intent_fail_not_signed() {
  let tx =
    mock_burn_intent_tx(
      BurnIntentTestCase {
        is_vault_oracle_input_present: True,
        is_vault_oracle_output_correct: True,
        is_app_oracle_ref_present: True,
        is_dex_order_book_ref_present: True,
        is_transfer_intent_present: True,
        is_transfer_amount_matching: True,
        is_intent_burn_correct: True,
        is_operation_signed: False,
      },
    )

  !l2_deposit_intent.l2_deposit_intent.mint(
    mock_vault_nft,
    build_redeemer(),
    mock_l2_deposit_intent_script_hash,
    tx,
  )
}
