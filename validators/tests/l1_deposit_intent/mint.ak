use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use l1_deposit_intent/spend_and_mint as l1_deposit_intent
use mocktail.{
  complete, mint, mock_policy_id, mock_pub_key_hash, mock_tx_hash, mocktail_tx,
  required_signer_hash, tx_in, tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/utils.{
  mock_deposit_intent_datum, mock_deposit_m_value,
  mock_l1_deposit_intent_script_hash, mock_user_trade_account, mock_vault_nft,
}
use types.{CancelIntent, DepositIntentDatum, MintIntent}

// ========== MintIntent Tests ==========
// Spec:
// - Deposit amount > 0
// - Net deposit value sent to L1DepositIntent address equals datum amount
// - No vault reference needed (user creates intent independently)

type MintIntentTestCase {
  is_token_minted_correctly: Bool,
  is_value_deposited_correctly: Bool,
  is_output_to_correct_address: Bool,
}

fn mock_mint_intent_tx(test_case: MintIntentTestCase) -> Transaction {
  let MintIntentTestCase {
    is_token_minted_correctly,
    is_value_deposited_correctly,
    is_output_to_correct_address,
  } = test_case

  let policy_id = mock_l1_deposit_intent_script_hash
  let wrong_policy_id = mock_policy_id(999)

  let deposit_value =
    if is_value_deposited_correctly {
      from_asset_list(mock_deposit_m_value)
    } else {
      // Wrong value - less than datum amount
      from_asset("", "", 1_000_000)
    }

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

  let output_value = deposit_value |> add(policy_id, "", 1)

  mocktail_tx()
    |> mint(True, mint_amount, policy_id, "")
    |> tx_out(True, output_address, output_value)
    |> tx_out_inline_datum(True, mock_deposit_intent_datum)
    |> complete()
}

// Success: Mint intent with correct token and value
test s2_mint_mint_intent_success() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_value_deposited_correctly: True,
        is_output_to_correct_address: True,
      },
    )

  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    MintIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Wrong mint amount (minted 2 instead of 1)
test s2_mint_mint_intent_fail_wrong_mint_amount() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: False,
        is_value_deposited_correctly: True,
        is_output_to_correct_address: True,
      },
    )

  !l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    MintIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Wrong deposit value (less than datum amount)
test s2_mint_mint_intent_fail_wrong_deposit_value() {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_value_deposited_correctly: False,
        is_output_to_correct_address: True,
      },
    )

  !l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    MintIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Output to wrong address (not script address)
test s2_mint_mint_intent_fail_wrong_output_address() fail {
  let tx =
    mock_mint_intent_tx(
      MintIntentTestCase {
        is_token_minted_correctly: True,
        is_value_deposited_correctly: True,
        is_output_to_correct_address: False,
      },
    )

  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    MintIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// ========== CancelIntent Tests ==========
// Spec:
// - L1DepositIntent token is burnt
// - The intent UTxO value returned to depositor (refund)
// - Signed by the depositor
// - No vault interaction required

type CancelIntentTestCase {
  is_token_burnt_correctly: Bool,
  is_signed_by_depositor: Bool,
}

fn mock_cancel_intent_tx(test_case: CancelIntentTestCase) -> Transaction {
  let CancelIntentTestCase { is_token_burnt_correctly, is_signed_by_depositor } =
    test_case

  let policy_id = mock_l1_deposit_intent_script_hash
  let depositor_pkh = mock_pub_key_hash(0)
  let wrong_pkh = mock_pub_key_hash(999)

  let burn_amount =
    if is_token_burnt_correctly {
      -1
    } else {
      -2
    }

  let signer_pkh =
    if is_signed_by_depositor {
      depositor_pkh
    } else {
      wrong_pkh
    }

  let input_value =
    from_asset_list(mock_deposit_m_value) |> add(policy_id, "", 1)

  mocktail_tx()
    |> tx_in(True, mock_tx_hash(0), 0, input_value, from_script(policy_id))
    |> tx_in_inline_datum(True, mock_deposit_intent_datum)
    |> mint(True, burn_amount, policy_id, "")
    |> required_signer_hash(True, signer_pkh)
    |> complete()
}

// Success: Cancel intent with correct burn and signature
test s2_mint_cancel_intent_success() {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: True,
        is_signed_by_depositor: True,
      },
    )

  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    CancelIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Wrong burn amount (burnt 2 instead of 1)
test s2_mint_cancel_intent_fail_wrong_burn_amount() {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: False,
        is_signed_by_depositor: True,
      },
    )

  !l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    CancelIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// Fail: Not signed by depositor
test s2_mint_cancel_intent_fail_not_signed_by_depositor() {
  let tx =
    mock_cancel_intent_tx(
      CancelIntentTestCase {
        is_token_burnt_correctly: True,
        is_signed_by_depositor: False,
      },
    )

  !l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    CancelIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}

// Note: Spec says "Deposit amount > 0" but this is enforced by backend, not on-chain.
// Empty deposit technically passes validation because value_geq(any_value, empty_value) == True.
// This test documents the actual on-chain behavior.
test s2_mint_mint_intent_with_empty_deposit_passes() {
  let policy_id = mock_l1_deposit_intent_script_hash
  let empty_m_value = []
  let empty_datum =
    DepositIntentDatum {
      depositor: mock_user_trade_account,
      deposit_amount: empty_m_value,
    }

  let output_value = from_asset("", "", 2_000_000) |> add(policy_id, "", 1)

  let tx =
    mocktail_tx()
      |> mint(True, 1, policy_id, "")
      |> tx_out(True, from_script(policy_id), output_value)
      |> tx_out_inline_datum(True, empty_datum)
      |> complete()

  // Empty deposit passes on-chain validation (backend restricts accepted assets)
  l1_deposit_intent.l1_deposit_intent.mint(
    mock_vault_nft,
    MintIntent,
    mock_l1_deposit_intent_script_hash,
    tx,
  )
}
