use aiken/collection/list
use cardano/address.{from_script}
use cardano/assets.{add, from_asset, from_lovelace}
use cardano/transaction.{InlineDatum, Input, NoDatum, Transaction}
use mocktail.{
  add_input, add_output, complete, mint, mock_output, mock_policy_id,
  mock_pub_key_address, mock_tx_hash, mock_utxo_ref, mocktail_tx, ref_tx_in,
  ref_tx_in_inline_datum, tx_in, tx_in_inline_datum, tx_out,
  tx_out_inline_datum,
}
use tests/utils.{
  mock_app_oracle, mock_app_oracle_address, mock_app_oracle_datum,
  mock_lp_record_script_hash, mock_message, mock_operator_charge_percentage,
  mock_signatures, mock_total_lp, mock_vault_balance, mock_vault_cost,
  mock_vault_oracle, mock_vault_oracle_address, mock_vault_oracle_datum,
  mock_vault_script_hash, mock_vault_state_datum, mock_vault_state_script_hash,
  mock_withdrawal_intent_datum, mock_withdrawal_intent_script_hash,
}
use tests/withdraw_utils/process_batch.{
  intent_input_a, intent_input_b, intent_input_c, intent_output_a,
  intent_output_b, intent_output_c, lp_amount_a, lp_amount_b, lp_amount_c,
}
use types.{
  BurnIntent, LPRecordDatum, MintIntent, VaultStateDatum, WithdrawalIntentDatum,
}
use withdraw_utils.{cal_per_user_operator_fee, convert_lp_to_usd}
use withdrawal_intent/spend_and_mint as withdrawal_intent_spend_and_mint

const usdm_policy = #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913"

const usdm_name = #"5553444d"

// ========== MintIntent Tests ==========

type MintWithdrawalIntentTestCase {
  is_withdrawal_intent_minted: Bool,
  is_amount_valid: Bool,
}

fn mock_mint_withdrawal_intent_tx(
  test_case: MintWithdrawalIntentTestCase,
) -> Transaction {
  let MintWithdrawalIntentTestCase {
    is_withdrawal_intent_minted,
    is_amount_valid,
  } = test_case

  let output_datum =
    if is_amount_valid {
      mock_withdrawal_intent_datum
    } else {
      WithdrawalIntentDatum {
        lp_address: mock_pub_key_address(0, None),
        amount: 0,
      }
    }

  mocktail_tx()
    |> mint(
        is_withdrawal_intent_minted,
        1,
        mock_withdrawal_intent_script_hash,
        "",
      )
    |> tx_out(
        True,
        from_script(mock_withdrawal_intent_script_hash),
        from_asset(mock_withdrawal_intent_script_hash, "", 1)
          |> add("", "", 2_000_000),
      )
    |> tx_out_inline_datum(True, output_datum)
    |> complete()
}

test s4_mint_success_mint_withdrawal_intent() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_withdrawal_intent_minted: True,
        is_amount_valid: True,
      },
    )

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_mint_withdrawal_intent_with_no_intent_minted() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_withdrawal_intent_minted: False,
        is_amount_valid: True,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_mint_withdrawal_intent_with_zero_amount() {
  let redeemer = MintIntent
  let tx =
    mock_mint_withdrawal_intent_tx(
      MintWithdrawalIntentTestCase {
        is_withdrawal_intent_minted: True,
        is_amount_valid: False,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

// ========== BurnIntent Tests ==========

// LP Record data reused from withdraw_utils tests
const lp_record_a_lp = 2_500_000_000_000

const lp_record_a_cost = 1_500_000

const lp_record_b_lp = 2_500_000_000_000

const lp_record_b_cost = 2_000_000

const lp_record_c_lp = 1_250_000_000_000

const lp_record_c_cost = 400_000

fn total_lp_withdrawn() -> Int {
  lp_amount_a + lp_amount_b + lp_amount_c
}

fn total_cost_removed() -> Int {
  lp_record_a_cost * lp_amount_a / lp_record_a_lp + lp_record_b_cost * lp_amount_b / lp_record_b_lp + lp_record_c_cost * lp_amount_c / lp_record_c_lp
}

fn total_user_receives() -> Int {
  let wv_a = convert_lp_to_usd(lp_amount_a, mock_total_lp, mock_vault_balance)
  let cb_a = lp_record_a_cost * lp_amount_a / lp_record_a_lp
  let fee_a =
    cal_per_user_operator_fee(wv_a, cb_a, mock_operator_charge_percentage)
  let ur_a = wv_a - fee_a

  let wv_b = convert_lp_to_usd(lp_amount_b, mock_total_lp, mock_vault_balance)
  let cb_b = lp_record_b_cost * lp_amount_b / lp_record_b_lp
  let fee_b =
    cal_per_user_operator_fee(wv_b, cb_b, mock_operator_charge_percentage)
  let ur_b = wv_b - fee_b

  let wv_c = convert_lp_to_usd(lp_amount_c, mock_total_lp, mock_vault_balance)
  let cb_c = lp_record_c_cost * lp_amount_c / lp_record_c_lp
  let fee_c =
    cal_per_user_operator_fee(wv_c, cb_c, mock_operator_charge_percentage)
  let ur_c = wv_c - fee_c

  ur_a + ur_b + ur_c
}

// LP Record inputs
const lp_record_input_a =
  Input {
    output_reference: mock_utxo_ref(50, 0),
    output: mock_output(
      from_script(mock_lp_record_script_hash),
      from_lovelace(2_000_000),
      InlineDatum(
        LPRecordDatum {
          address: mock_pub_key_address(0, None),
          lp: lp_record_a_lp,
          cost: lp_record_a_cost,
        },
      ),
      None,
    ),
  }

const lp_record_input_b =
  Input {
    output_reference: mock_utxo_ref(51, 0),
    output: mock_output(
      from_script(mock_lp_record_script_hash),
      from_lovelace(2_000_000),
      InlineDatum(
        LPRecordDatum {
          address: mock_pub_key_address(1, None),
          lp: lp_record_b_lp,
          cost: lp_record_b_cost,
        },
      ),
      None,
    ),
  }

const lp_record_input_c =
  Input {
    output_reference: mock_utxo_ref(52, 0),
    output: mock_output(
      from_script(mock_lp_record_script_hash),
      from_lovelace(2_000_000),
      InlineDatum(
        LPRecordDatum {
          address: mock_pub_key_address(2, None),
          lp: lp_record_c_lp,
          cost: lp_record_c_cost,
        },
      ),
      None,
    ),
  }

// LP Record outputs for partial withdrawals
const lp_record_output_a =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2_000_000),
    InlineDatum(
      LPRecordDatum {
        address: mock_pub_key_address(0, None),
        lp: lp_record_a_lp - lp_amount_a,
        cost: lp_record_a_cost - lp_record_a_cost * lp_amount_a / lp_record_a_lp,
      },
    ),
    None,
  )

const lp_record_output_c =
  mock_output(
    from_script(mock_lp_record_script_hash),
    from_lovelace(2_000_000),
    InlineDatum(
      LPRecordDatum {
        address: mock_pub_key_address(2, None),
        lp: lp_record_c_lp - lp_amount_c,
        cost: lp_record_c_cost - lp_record_c_cost * lp_amount_c / lp_record_c_lp,
      },
    ),
    None,
  )

type BurnWithdrawalIntentTestCase {
  is_vault_oracle_ref_inputed: Bool,
  is_app_oracle_ref_inputed: Bool,
  is_vault_state_output_datum_correct: Bool,
  is_vault_state_output_clean: Bool,
  is_intent_burn_amount_correct: Bool,
  is_vault_unlock_correct: Bool,
}

// Outputs: [0]=vault_state, [1]=vault_output, [2]=user_b, [3]=user_a, [4]=user_c, [5]=lp_record_a, [6]=lp_record_c
const burn_indices = [3, 2, 4]

const burn_lp_indices = [5, 6]

fn mock_burn_withdrawal_intent_tx(
  test_case: BurnWithdrawalIntentTestCase,
) -> Transaction {
  let BurnWithdrawalIntentTestCase {
    is_vault_oracle_ref_inputed,
    is_app_oracle_ref_inputed,
    is_vault_state_output_datum_correct,
    is_vault_state_output_clean,
    is_intent_burn_amount_correct,
    is_vault_unlock_correct,
  } = test_case

  let vault_oracle_ref_input_value =
    from_asset(mock_vault_oracle, "", 1) |> add("", "", 2_000_000)

  let app_oracle_ref_input_value =
    from_asset(mock_app_oracle, "", 1) |> add("", "", 2_000_000)

  let vault_state_input_value =
    from_asset(mock_vault_state_script_hash, "", 1) |> add("", "", 2_000_000)

  let vault_state_output_datum =
    if is_vault_state_output_datum_correct {
      VaultStateDatum {
        ..mock_vault_state_datum,
        total_lp: mock_total_lp - total_lp_withdrawn(),
        vault_cost: mock_vault_cost - total_cost_removed(),
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
      -list.length(burn_indices)
    } else {
      -1
    }

  // Vault: supply enough USDM (price=1) so the difference matches total_user_receives
  let vault_from_amount = 5_000_000
  let vault_to_amount =
    if is_vault_unlock_correct {
      vault_from_amount - total_user_receives()
    } else {
      vault_from_amount
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
    |> tx_out(
        True,
        from_script(mock_vault_script_hash),
        from_asset(usdm_policy, usdm_name, vault_to_amount),
      )
    |> mint(True, intent_burn_amount, mock_withdrawal_intent_script_hash, "")
    |> mint(True, -1, mock_lp_record_script_hash, "")
    |> complete()
    |> add_input(
        True,
        Input {
          output_reference: mock_utxo_ref(10, 0),
          output: mock_output(
            from_script(mock_vault_script_hash),
            from_asset(usdm_policy, usdm_name, vault_from_amount),
            NoDatum,
            None,
          ),
        },
      )
    |> add_input(True, intent_input_a)
    |> add_input(True, intent_input_b)
    |> add_input(True, intent_input_c)
    |> add_input(True, lp_record_input_a)
    |> add_input(True, lp_record_input_b)
    |> add_input(True, lp_record_input_c)
    |> add_output(True, intent_output_b)
    |> add_output(True, intent_output_a)
    |> add_output(True, intent_output_c)
    |> add_output(True, lp_record_output_a)
    |> add_output(True, lp_record_output_c)
}

test s4_mint_success_burn_withdrawal_intent() {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_vault_unlock_correct: True,
      },
    )

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_burn_withdrawal_intent_with_no_vault_oracle_ref() fail {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: False,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_vault_unlock_correct: True,
      },
    )

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_burn_withdrawal_intent_with_no_app_oracle_ref() fail {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: False,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_vault_unlock_correct: True,
      },
    )

  withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_burn_withdrawal_intent_with_incorrect_vault_state_datum() {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: False,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_vault_unlock_correct: True,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_burn_withdrawal_intent_with_unclean_vault_state_output() {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: False,
        is_intent_burn_amount_correct: True,
        is_vault_unlock_correct: True,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_burn_withdrawal_intent_with_incorrect_intent_burn() {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: False,
        is_vault_unlock_correct: True,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}

test s4_mint_fail_burn_withdrawal_intent_with_incorrect_vault_unlock() {
  let redeemer =
    BurnIntent(burn_indices, burn_lp_indices, mock_message, mock_signatures)
  let tx =
    mock_burn_withdrawal_intent_tx(
      BurnWithdrawalIntentTestCase {
        is_vault_oracle_ref_inputed: True,
        is_app_oracle_ref_inputed: True,
        is_vault_state_output_datum_correct: True,
        is_vault_state_output_clean: True,
        is_intent_burn_amount_correct: True,
        is_vault_unlock_correct: False,
      },
    )

  !withdrawal_intent_spend_and_mint.withdrawal_intent.mint(
    mock_vault_oracle,
    redeemer,
    mock_withdrawal_intent_script_hash,
    tx,
  )
}
