use cardano/address.{from_script}
use cardano/assets.{add, from_asset}
use cardano/transaction.{Transaction}
use lp_record/spend_mint as lp_record_spend_mint
use mocktail.{
  complete, mint, mock_tx_hash, mock_utxo_ref, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, tx_in, tx_in_inline_datum,
}
use tests/utils.{
  mock_deposit_intent_script_hash, mock_lp_record_script_hash,
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_withdrawal_intent_script_hash,
}
use types.{BurnLPRecord, LPRecordDatum, MintLPRecord}

// ========== Spend Tests ==========

type SpendLPRecordTestCase {
  is_vault_oracle_ref_inputed: Bool,
  is_deposit_intent_burned: Bool,
  is_withdrawal_intent_burned: Bool,
}

fn mock_spend_lp_record_tx(test_case: SpendLPRecordTestCase) -> Transaction {
  let SpendLPRecordTestCase {
    is_vault_oracle_ref_inputed,
    is_deposit_intent_burned,
    is_withdrawal_intent_burned,
  } = test_case

  let vault_oracle_ref_input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let input_value =
    from_asset(mock_lp_record_script_hash, "", 1) |> add("", "", 2_000_000)

  let lp_record_datum: Data =
    LPRecordDatum {
      address: mocktail.mock_pub_key_address(0, None),
      lp: 1_000_000,
      cost: 500_000,
    }

  mocktail_tx()
    |> tx_in(
        True,
        mock_tx_hash(0),
        0,
        input_value,
        from_script(mock_lp_record_script_hash),
      )
    |> tx_in_inline_datum(True, lp_record_datum)
    |> ref_tx_in(
        is_vault_oracle_ref_inputed,
        mock_tx_hash(1),
        0,
        vault_oracle_ref_input_value,
        mock_vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_vault_oracle_ref_inputed, mock_vault_oracle_datum)
    |> mint(is_deposit_intent_burned, -1, mock_deposit_intent_script_hash, "")
    |> mint(
        is_withdrawal_intent_burned,
        -1,
        mock_withdrawal_intent_script_hash,
        "",
      )
    |> complete()
}

test s5_spend_success_with_deposit_intent_burned() {
  let tx =
    mock_spend_lp_record_tx(
      SpendLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: True,
        is_withdrawal_intent_burned: False,
      },
    )

  lp_record_spend_mint.lp_record.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s5_spend_success_with_withdrawal_intent_burned() {
  let tx =
    mock_spend_lp_record_tx(
      SpendLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: True,
      },
    )

  lp_record_spend_mint.lp_record.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s5_spend_fail_without_vault_oracle_ref() fail {
  let tx =
    mock_spend_lp_record_tx(
      SpendLPRecordTestCase {
        is_vault_oracle_ref_inputed: False,
        is_deposit_intent_burned: True,
        is_withdrawal_intent_burned: False,
      },
    )

  lp_record_spend_mint.lp_record.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

test s5_spend_fail_without_any_intent_burned() {
  let tx =
    mock_spend_lp_record_tx(
      SpendLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: False,
      },
    )

  !lp_record_spend_mint.lp_record.spend(
    mock_vault_oracle,
    None,
    None,
    mock_utxo_ref(0, 0),
    tx,
  )
}

// ========== Mint Tests ==========

type MintLPRecordTestCase {
  is_vault_oracle_ref_inputed: Bool,
  is_deposit_intent_burned: Bool,
  is_withdrawal_intent_burned: Bool,
}

fn mock_mint_lp_record_tx(test_case: MintLPRecordTestCase) -> Transaction {
  let MintLPRecordTestCase {
    is_vault_oracle_ref_inputed,
    is_deposit_intent_burned,
    is_withdrawal_intent_burned,
  } = test_case

  let vault_oracle_ref_input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  mocktail_tx()
    |> ref_tx_in(
        is_vault_oracle_ref_inputed,
        mock_tx_hash(1),
        0,
        vault_oracle_ref_input_value,
        mock_vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_vault_oracle_ref_inputed, mock_vault_oracle_datum)
    |> mint(True, 1, mock_lp_record_script_hash, "")
    |> mint(is_deposit_intent_burned, -1, mock_deposit_intent_script_hash, "")
    |> mint(
        is_withdrawal_intent_burned,
        -1,
        mock_withdrawal_intent_script_hash,
        "",
      )
    |> complete()
}

test s5_mint_success_mint_lp_record_with_deposit_intent_burned() {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: True,
        is_withdrawal_intent_burned: False,
      },
    )

  lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    MintLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

test s5_mint_fail_mint_lp_record_without_vault_oracle_ref() fail {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: False,
        is_deposit_intent_burned: True,
        is_withdrawal_intent_burned: False,
      },
    )

  lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    MintLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

test s5_mint_fail_mint_lp_record_without_deposit_intent_burned() {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: True,
      },
    )

  !lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    MintLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

test s5_mint_fail_mint_lp_record_with_no_intent_burned() {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: False,
      },
    )

  !lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    MintLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

// ========== Burn Tests ==========

test s5_mint_success_burn_lp_record_with_withdrawal_intent_burned() {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: True,
      },
    )

  lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    BurnLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

test s5_mint_fail_burn_lp_record_without_vault_oracle_ref() fail {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: False,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: True,
      },
    )

  lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    BurnLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

test s5_mint_fail_burn_lp_record_without_withdrawal_intent_burned() {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: True,
        is_withdrawal_intent_burned: False,
      },
    )

  !lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    BurnLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}

test s5_mint_fail_burn_lp_record_with_no_intent_burned() {
  let tx =
    mock_mint_lp_record_tx(
      MintLPRecordTestCase {
        is_vault_oracle_ref_inputed: True,
        is_deposit_intent_burned: False,
        is_withdrawal_intent_burned: False,
      },
    )

  !lp_record_spend_mint.lp_record.mint(
    mock_vault_oracle,
    BurnLPRecord,
    mock_lp_record_script_hash,
    tx,
  )
}
