use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_asset_list}
use cardano/transaction.{Transaction}
use deposit_intent/spend_and_mint as deposit_intent_spend_and_mint
use deposit_utils.{cal_lp_token_amount,
  combine_m_value, convert_m_value_to_usdm}
use mocktail.{
  add_input, add_output, complete, mint, mock_policy_id, mock_tx_hash,
  mock_utxo_ref, mocktail_tx, ref_tx_in, ref_tx_in_inline_datum, tx_in,
  tx_in_inline_datum, tx_out, tx_out_inline_datum,
}
use tests/deposit_utils/process_batch.{
  intent_input_a, intent_input_b, intent_input_c, intent_output_a,
  intent_output_b, intent_output_c, m_value_a, m_value_b, m_value_c, prices,
}
use tests/utils.{
  mock_app_deposit_request_address, mock_app_deposit_request_token,
  mock_app_oracle, mock_app_oracle_address, mock_deposit_intent_datum,
  mock_deposit_intent_script_hash, mock_deposit_m_value, mock_input_oracle_datum,
  mock_lp_token, mock_message, mock_operator_fee, mock_pluggable_logic,
  mock_signatures, mock_total_lp, mock_vault_balance, mock_vault_cost,
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
  to_mvalue,
}
use types.{BurnIntent, MValue, MintIntent, VaultOracleDatum}

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

  let deposit_value: MValue =
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

test s2_mint_success_mint_deposit_intent() {
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

test s2_mint_fail_mint_deposit_intent_with_no_intent_minted() {
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

test s2_mint_fail_mint_deposit_intent_with_intent_output_not_clean() {
  let redeemer = MintIntent
  let tx =
    mock_mint_deposit_intent_tx(
      MintDepositIntentTestCase {
        is_deposit_intent_minted: True,
        is_token_output_clean: False,
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

test s2_mint_fail_mint_deposit_intent_with_value_deposited_incorrect() {
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

type BurnDepositIntentTestCase {
  is_vault_oracle_inputed: Bool,
  is_app_oracle_ref_inputed: Bool,
  is_vault_output_datum_correct: Bool,
  is_vault_output_value_clean: Bool,
  is_lp_mint_amount_correct: Bool,
  is_intent_burn_amount_correct: Bool,
  is_app_deposit_request_output_correct: Bool,
}

const indices = [2, 3, 4]

const utxo_ref = mock_utxo_ref(0, 0)

fn mock_burn_deposit_intent_tx(
  test_case: BurnDepositIntentTestCase,
) -> Transaction {
  let BurnDepositIntentTestCase {
    is_vault_oracle_inputed,
    is_app_oracle_ref_inputed,
    is_vault_output_datum_correct,
    is_vault_output_value_clean,
    is_lp_mint_amount_correct,
    is_intent_burn_amount_correct,
    is_app_deposit_request_output_correct,
  } = test_case

  let vault_oracle_input_value =
    if is_vault_oracle_inputed {
      from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)
    } else {
      from_asset("", "", 1) |> add("", "", 1)
    }

  let vault_oracle_output_value =
    if is_vault_output_value_clean {
      from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)
    } else {
      from_asset(mock_vault_oracle, "", 1)
        |> add("", "", 2_000_000)
        |> add(mock_policy_id(999), "", 1)
    }

  let app_oracle_ref_input_value =
    if is_app_oracle_ref_inputed {
      from_asset(mock_app_oracle, "", 1)
        |> add("", "", 2_000_000)
    } else {
      from_asset("", "", 1) |> add("", "", 1) |> add(mock_policy_id(999), "", 1)
    }

  let total_intent_datum_usdm_value =
    convert_m_value_to_usdm(m_value_a, prices) + convert_m_value_to_usdm(
      m_value_b,
      prices,
    ) + convert_m_value_to_usdm(m_value_c, prices)

  trace total_intent_datum_usdm_value

  //attention: handle rounding error
  let total_lp_token_minted =
    if is_lp_mint_amount_correct {
      cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_a, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ) + cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_b, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ) + cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_c, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      )
    } else {
      cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_a, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ) + cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_b, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ) + cal_lp_token_amount(
        convert_m_value_to_usdm(m_value_c, prices),
        mock_vault_balance,
        mock_total_lp,
        mock_operator_fee,
      ) + 1
    }

  let vault_output_datum =
    if is_vault_output_datum_correct {
      VaultOracleDatum {
        ..mock_vault_oracle_datum,
        total_lp: mock_total_lp + total_lp_token_minted,
        hwm_lp_value: mock_vault_balance - mock_operator_fee + total_intent_datum_usdm_value,
        vault_cost: mock_vault_cost + total_intent_datum_usdm_value,
      }
    } else {
      VaultOracleDatum {
        ..mock_vault_oracle_datum,
        total_lp: mock_total_lp + total_lp_token_minted + 1,
        hwm_lp_value: mock_vault_balance - mock_operator_fee + total_intent_datum_usdm_value,
        vault_cost: mock_vault_cost + total_intent_datum_usdm_value,
      }
    }

  let intent_burn_amount =
    if is_intent_burn_amount_correct {
      3
    } else {
      3 + 1
    }

  let app_deposit_request_output_value =
    if is_app_deposit_request_output_correct {
      from_asset_list(
        combine_m_value(combine_m_value(m_value_a, m_value_b), m_value_c),
      )
        |> add(mock_app_deposit_request_token, "", 1)
    } else {
      from_asset_list(
        combine_m_value(combine_m_value(m_value_a, m_value_b), []),
      )
        |> add(mock_app_deposit_request_token, "", 1)
    }
  mocktail_tx()
    |> tx_in(
        True,
        utxo_ref.transaction_id,
        utxo_ref.output_index,
        vault_oracle_input_value,
        mock_vault_oracle_address,
      )
    |> tx_in_inline_datum(is_vault_oracle_inputed, mock_vault_oracle_datum)
    |> ref_tx_in(
        True,
        mock_tx_hash(0),
        1,
        app_oracle_ref_input_value,
        mock_app_oracle_address,
      )
    |> ref_tx_in_inline_datum(
        is_app_oracle_ref_inputed,
        mock_input_oracle_datum,
      )
    |> tx_out(True, mock_vault_oracle_address, vault_oracle_output_value)
    |> tx_out_inline_datum(True, vault_output_datum)
    |> mint(True, total_lp_token_minted, mock_lp_token, mock_pluggable_logic)
    |> mint(True, -intent_burn_amount, mock_deposit_intent_script_hash, "")
    |> tx_out(
        True,
        mock_app_deposit_request_address,
        app_deposit_request_output_value,
      )
    |> complete()
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_b)
    |> add_input(True, intent_input_c)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_b)
    |> add_output(True, intent_output_c)
}

test s2_mint_success_burn_deposit_intent() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_no_vault_oracle_input() fail {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: False,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_no_app_oracle_ref_input() fail {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: False,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_incorrect_vault_output_datum() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: False,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_incorrect_vault_output_value() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: False,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_incorrect_lp_mint_amount() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: False,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_incorrect_intent_burn_amount() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: False,
        is_app_deposit_request_output_correct: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_incorrect_app_deposit_request_output() {
  let redeemer = BurnIntent(indices, mock_message, mock_signatures)
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: False,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_signed_utxo_not_spent() {
  let redeemer =
    BurnIntent(
      indices,
      #"d8799f1ad9133796a25820c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c9135553444d014002d8799f5820cd82a190d3b4ef95a50bd791882959f541e308adb69b12d022d94a6d9f02bcf001ffff",
      [
        #"eded05b711ad2f58742a959aa06d4301604e59e88b06cb4bd50c36eef55f5610da3675f9b905e83614ae92f2e47593de9e8f827230f0d0bd8df2333d86615703",
        #"f4fdb2071f658019249a01894d817daa113e7563d7e6510ba043e4220f60e4a3ae551b87facbf4fd4f1810a462c8031b9c555f7ac74074e8048cf6a510c42c09",
        #"b3641e70b7fd71838511363cfe08bf0e28bef69687ce08c134d0fe42298244f03546a5699739e105613edc47452c15175d98ca112467f8979b90274c4c6cbf0a",
      ],
    )
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}

test s2_mint_fail_burn_deposit_intent_with_incorrect_signatures() {
  let redeemer =
    BurnIntent(
      indices,
      mock_message,
      [
        #"08e454f591121b1a09fd0073fdf66740bad3f1382dcfc499e91a996f601c7c8909e4b0a0b8fe64e68514f315ffdd02944c369ef2a9ce22a3dec14b60b0109e0d",
        #"f18d0e8aab34dc74d633df4310d8bf49809627d4bd4ef0ee8fa3b3ba47deb9e804de031e015521359c1d69070266f3d4423a07994f424782ceeaa8413739160c",
        #"4d2a670fed48e57b7c2d4d582afd5f24378a2b93c3794dce409c15fe59b417c08ba8b598f8e9b6ffd68374f5eac79a7588cc218d4d58251b3992db10d01e100a",
      ],
    )
  let tx =
    mock_burn_deposit_intent_tx(
      BurnDepositIntentTestCase {
        is_vault_oracle_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_output_datum_correct: True,
        is_vault_output_value_clean: True,
        is_lp_mint_amount_correct: True,
        is_intent_burn_amount_correct: True,
        is_app_deposit_request_output_correct: True,
      },
    )

  !deposit_intent_spend_and_mint.deposit_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_deposit_intent_script_hash,
    tx,
  )
}
