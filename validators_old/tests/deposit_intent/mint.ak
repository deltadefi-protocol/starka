use aiken/collection/list
use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use deposit_intent/spend_and_mint as deposit_intent_spend_and_mint
use deposit_utils.{cal_lp_amount, combine_m_value}
use mocktail.{
  add_input, add_output, complete, mint, mock_policy_id, mock_tx_hash,
  mock_utxo_ref, mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use price_oracle_utils.{convert_m_value_to_usd}
use tests/deposit_utils/process_batch.{
  intent_input_a, intent_input_b, intent_input_c, intent_output_a,
  intent_output_b, intent_output_c, m_value_a, m_value_b, m_value_c, prices,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_deposit_intent_datum, mock_deposit_intent_script_hash,
  mock_deposit_m_value, mock_lp_record_script_hash, mock_message,
  mock_signatures, mock_total_lp, mock_vault_balance, mock_vault_cost,
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_vault_script_hash, mock_vault_state_datum, mock_vault_state_script_hash,
  to_mvalue,
}
use types.{BurnIntent, MintIntent, VaultStateDatum}

// ========== MintIntent Tests ==========

type MintDepositIntentTestCase {
  is_deposit_intent_minted: Bool,
  is_token_output_clean: Bool,
  is_value_deposited_correctly: Bool,
}

fn mock_mint_deposit_intent_tx(
  test_case: MintDepositIntentTestCase,
) -> Transaction {
  let MintDepositIntentTestCase {
    is_deposit_intent_minted,
    is_token_output_clean,
    is_value_deposited_correctly,
  } = test_case

  let deposit_value =
    if is_value_deposited_correctly {
      mock_deposit_m_value
    } else {
      from_asset("A", "abc", 1)
        |> add("C", "def", 10)
        |> to_mvalue()
    }
  let output_datum = mock_deposit_intent_datum
  mocktail_tx()
    |> mint(is_deposit_intent_minted, 1, mock_deposit_intent_script_hash, "")
    |> tx_out(
        is_token_output_clean,
        from_script(mock_deposit_intent_script_hash),
        from_asset_list(deposit_value)
          |> add(mock_deposit_intent_script_hash, "", 1),
      )
    |> tx_out(
        !is_token_output_clean,
        from_script(mock_deposit_intent_script_hash),
        from_asset_list(deposit_value)
          |> add(mock_deposit_intent_script_hash, "", 1)
          |> add(mock_policy_id(999), "", 1),
      )
    |> tx_out_inline_datum(True, output_datum)
    |> complete()
}

test s3_mint_success_mint_deposit_intent() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: True,
        is_token_output_clean: True,
        is_value_deposited_correctly: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_mint_deposit_intent_with_no_intent_minted() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: False,
        is_token_output_clean: True,
        is_value_deposited_correctly: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_mint_deposit_intent_with_value_deposited_incorrect() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: True,
        is_token_output_clean: True,
        is_value_deposited_correctly: False,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

// ========== BurnIntent Tests ==========

type BurnDepositIntentTestCase {
  is_vault_oracle_ref_inputed: Bool,
  is_app_oracle_ref_inputed: Bool,
  is_vault_state_output_datum_correct: Bool,
  is_vault_state_output_clean: Bool,
  is_intent_burn_amount_correct: Bool,
  is_deposit_sent_to_vault: Bool,
}

// Indices offset by 2 because outputs[0]=vault_state, outputs[1]=vault_deposit
// Then LP Record outputs: [2]=intent_output_b, [3]=intent_output_a, [4]=intent_output_c
// Intent A→3, Intent B→2, Intent C→4
const indices = [3, 2, 4]

fn mock_burn_deposit_intent_tx(
  test_case: BurnDepositIntentTestCase,
) -> Transaction {
  let BurnDepositIntentTestCase {
    is_vault_oracle_ref_inputed,
    is_app_oracle_ref_inputed,
    is_vault_state_output_datum_correct,
    is_vault_state_output_clean,
    is_intent_burn_amount_correct,
    is_deposit_sent_to_vault,
  } = test_case

  let vault_oracle_ref_input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let app_oracle_ref_input_value =
    from_asset(mock_app_oracle, "", 1)
      |> add("", "", 2_000_000)

  let vault_state_input_value =
    from_asset(mock_vault_state_script_hash, "", 1) |> add("", "", 2_000_000)

  // Calculate totals from batch processing
  let total_lp_added =
    cal_lp_amount(
      convert_m_value_to_usd(m_value_a, prices),
      mock_vault_balance,
      mock_total_lp,
    ) + cal_lp_amount(
      convert_m_value_to_usd(m_value_b, prices),
      mock_vault_balance,
      mock_total_lp,
    ) + cal_lp_amount(
      convert_m_value_to_usd(m_value_c, prices),
      mock_vault_balance,
      mock_total_lp,
    )

  let total_usd =
    convert_m_value_to_usd(m_value_a, prices) + convert_m_value_to_usd(
      m_value_b,
      prices,
    ) + convert_m_value_to_usd(m_value_c, prices)

  let vault_state_output_datum =
    if is_vault_state_output_datum_correct {
      VaultStateDatum {
        ..mock_vault_state_datum,
        total_lp: mock_total_lp + total_lp_added,
        vault_cost: mock_vault_cost + total_usd,
      }
    } else {
      mock_vault_state_datum
    }

  let vault_state_output_value =
    if is_vault_state_output_clean {
      from_asset(mock_vault_state_script_hash, "", 1) |> add("", "", 2_000_000)
    } else {
      from_asset(mock_vault_state_script_hash, "", 1)
        |> add("", "", 2_000_000)
        |> add(mock_policy_id(999), "", 1)
    }

  let intent_burn_amount =
    if is_intent_burn_amount_correct {
      -list.length(indices)
    } else {
      -1
    }

  // Combined m_value to send to vault
  let total_m_value =
    combine_m_value(combine_m_value(m_value_a, m_value_b), m_value_c)

  let vault_output_value =
    if is_deposit_sent_to_vault {
      from_asset_list(total_m_value)
    } else {
      from_asset("", "", 1_000_000)
    }

  // Input matching utxo_ref in mock_message: mock_utxo_ref(0, 0)
  mocktail_tx()
    |> tx_in(
        True,
        mock_tx_hash(0),
        0,
        vault_state_input_value,
        from_script(mock_vault_state_script_hash),
      )
    |> tx_in_inline_datum(True, mock_vault_state_datum)
    |> ref_tx_in(
        is_vault_oracle_ref_inputed,
        mock_tx_hash(1),
        0,
        vault_oracle_ref_input_value,
        mock_vault_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_vault_oracle_ref_inputed, mock_vault_oracle_datum)
    |> ref_tx_in(
        is_app_oracle_ref_inputed,
        mock_tx_hash(2),
        0,
        app_oracle_ref_input_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(is_app_oracle_ref_inputed, mock_app_oracle_datum)
    |> tx_out(
        True,
        from_script(mock_vault_state_script_hash),
        vault_state_output_value,
      )
    |> tx_out_inline_datum(True, vault_state_output_datum)
    |> tx_out(True, from_script(mock_vault_script_hash), vault_output_value)
    |> mint(
        True,
        intent_burn_amount,
        mock_deposit_intent_script_hash,
        "",
      )
    |> mint(True, 3, mock_lp_record_script_hash, "")
    |> complete()
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_b)
    |> add_input(True, intent_input_c)
    |> add_output(True, intent_output_b)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_c)
}

test s3_mint_success_burn_deposit_intent() {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_deposit_sent_to_vault: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_burn_deposit_intent_with_no_vault_oracle_ref() fail {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: False,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_deposit_sent_to_vault: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_burn_deposit_intent_with_no_app_oracle_ref() fail {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: False,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_deposit_sent_to_vault: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_burn_deposit_intent_with_incorrect_vault_state_datum() {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: False,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_deposit_sent_to_vault: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_burn_deposit_intent_with_unclean_vault_state_output() {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: False,
        is_intent_burn_amount_correct: True,
        is_deposit_sent_to_vault: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_burn_deposit_intent_with_incorrect_intent_burn() {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: False,
        is_deposit_sent_to_vault: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s3_mint_fail_burn_deposit_intent_with_deposit_not_sent() {
  let redeemer = BurnIntent(indices, [], mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_deposit_sent_to_vault: False,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}
