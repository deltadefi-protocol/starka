use cardano/address.{from_script}
use cardano/assets.{from_asset, from_lovelace}
use cardano/transaction.{InlineDatum, Input, NoDatum}
use mocktail.{mock_output, mock_pub_key_address, mock_utxo_ref}
use tests/utils.{
  mock_lp_token, mock_operator_fee, mock_pluggable_logic, mock_total_lp,
  mock_vault_balance, mock_vault_script_hash, mock_withdrawal_intent_script_hash,
}
use types.{WithdrawalIntentDatum}
use withdraw_utils.{
  convert_lp_to_usdm, process_batched_withdrawal_intent_validation,
}

pub const lp_amount_a: Int = 1000000

pub const lp_amount_b: Int = 2000000

pub const lp_amount_c: Int = 1000

pub const prices: Pairs<ByteArray, Int> =
  [
    Pair(#"", 2),
    Pair(#"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c9135553444d", 1),
  ]

const withdrawal_intent_datum_a: Data =
  WithdrawalIntentDatum {
    lp_address: mock_pub_key_address(0, None),
    amount: lp_amount_a,
  }

const withdrawal_intent_datum_b: Data =
  WithdrawalIntentDatum {
    lp_address: mock_pub_key_address(1, None),
    amount: lp_amount_b,
  }

const withdrawal_intent_datum_c: Data =
  WithdrawalIntentDatum {
    lp_address: mock_pub_key_address(2, None),
    amount: lp_amount_c,
  }

const input_x =
  Input {
    output_reference: mock_utxo_ref(99, 0),
    output: mock_output(
      mock_pub_key_address(999, None),
      from_lovelace(1000000),
      NoDatum,
      None,
    ),
  }

const input_y =
  Input {
    output_reference: mock_utxo_ref(99, 1),
    output: mock_output(
      mock_pub_key_address(999, None),
      from_lovelace(1000000),
      NoDatum,
      None,
    ),
  }

pub const vault_input_a =
  Input {
    output_reference: mock_utxo_ref(10, 0),
    output: mock_output(
      from_script(mock_vault_script_hash),
      from_asset(
        #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
        #"5553444d",
        convert_lp_to_usdm(
          lp_amount_a,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ) + convert_lp_to_usdm(
          lp_amount_b,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ) + convert_lp_to_usdm(
          lp_amount_c,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ),
      ),
      NoDatum,
      None,
    ),
  }

pub const vault_input_b =
  Input {
    output_reference: mock_utxo_ref(10, 0),
    output: mock_output(
      from_script(mock_vault_script_hash),
      from_asset(
        #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
        #"5553444d",
        convert_lp_to_usdm(
          lp_amount_a,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ) + convert_lp_to_usdm(
          lp_amount_b,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ) + convert_lp_to_usdm(
          lp_amount_c,
          mock_total_lp,
          mock_vault_balance,
          mock_operator_fee,
        ),
      ),
      NoDatum,
      None,
    ),
  }

pub const vault_output =
  mock_output(
    from_script(mock_vault_script_hash),
    from_asset(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      #"5553444d",
      convert_lp_to_usdm(
        lp_amount_a,
        mock_total_lp,
        mock_vault_balance,
        mock_operator_fee,
      ) + convert_lp_to_usdm(
        lp_amount_b,
        mock_total_lp,
        mock_vault_balance,
        mock_operator_fee,
      ) + convert_lp_to_usdm(
        lp_amount_c,
        mock_total_lp,
        mock_vault_balance,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

pub const intent_input_a =
  Input {
    output_reference: mock_utxo_ref(0, 0),
    output: mock_output(
      from_script(mock_withdrawal_intent_script_hash),
      from_asset(mock_lp_token, mock_pluggable_logic, lp_amount_a),
      InlineDatum(withdrawal_intent_datum_a),
      None,
    ),
  }

pub const intent_input_b =
  Input {
    output_reference: mock_utxo_ref(1, 0),
    output: mock_output(
      from_script(mock_withdrawal_intent_script_hash),
      from_asset(mock_lp_token, mock_pluggable_logic, lp_amount_b),
      InlineDatum(withdrawal_intent_datum_b),
      None,
    ),
  }

pub const intent_input_c =
  Input {
    output_reference: mock_utxo_ref(2, 0),
    output: mock_output(
      from_script(mock_withdrawal_intent_script_hash),
      from_asset(mock_lp_token, mock_pluggable_logic, lp_amount_c),
      InlineDatum(withdrawal_intent_datum_c),
      None,
    ),
  }

pub const intent_output_a =
  mock_output(
    mock_pub_key_address(0, None),
    from_asset(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      #"5553444d",
      convert_lp_to_usdm(
        lp_amount_a,
        mock_total_lp,
        mock_vault_balance,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

pub const intent_output_b =
  mock_output(
    mock_pub_key_address(1, None),
    from_asset(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      #"5553444d",
      convert_lp_to_usdm(
        lp_amount_b,
        mock_total_lp,
        mock_vault_balance,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

pub const intent_output_c =
  mock_output(
    mock_pub_key_address(2, None),
    from_asset(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      #"5553444d",
      convert_lp_to_usdm(
        lp_amount_c,
        mock_total_lp,
        mock_vault_balance,
        mock_operator_fee,
      ),
    ),
    NoDatum,
    None,
  )

const inputs =
  [
    input_x, intent_input_a, intent_input_b, input_y, intent_input_c,
    vault_input_a, vault_input_b,
  ]

const excessive_inputs =
  [
    input_x, intent_input_a, intent_input_b, input_y, intent_input_c,
    intent_input_c, vault_input_a, vault_input_b,
  ]

const insufficient_inputs =
  [
    input_x, intent_input_a, intent_input_b, input_y, vault_input_a,
    vault_input_b,
  ]

const outputs = [intent_output_b, intent_output_a, intent_output_c]

const incorrect_outputs = [intent_output_a, intent_output_b, intent_output_c]

const indices = [1, 0, 2]

const incorrect_indices = [0, 1, 2]

const excessive_indices = [0, 1, 2, 3]

test process_batch_normal() {
  let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
    process_batched_withdrawal_intent_validation(
      inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_withdrawal_intent_script_hash,
    )

  (total_intent_datum_lp_amount == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_intent_datum_lp_usdm_value == convert_lp_to_usdm(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ))?
}

test process_batch_excessive_inputs() fail {
  let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
    process_batched_withdrawal_intent_validation(
      excessive_inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_withdrawal_intent_script_hash,
    )

  (total_intent_datum_lp_amount == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_intent_datum_lp_usdm_value == convert_lp_to_usdm(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ))?
}

test process_batch_insufficient_inputs() fail {
  let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
    process_batched_withdrawal_intent_validation(
      insufficient_inputs,
      outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_withdrawal_intent_script_hash,
    )

  (total_intent_datum_lp_amount == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_intent_datum_lp_usdm_value == convert_lp_to_usdm(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ))?
}

test process_batch_incorrect_outputs() fail {
  let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
    process_batched_withdrawal_intent_validation(
      inputs,
      incorrect_outputs,
      indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_withdrawal_intent_script_hash,
    )

  (total_intent_datum_lp_amount == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_intent_datum_lp_usdm_value == convert_lp_to_usdm(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ))?
}

test process_batch_incorrect_indices() fail {
  let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
    process_batched_withdrawal_intent_validation(
      inputs,
      outputs,
      incorrect_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_withdrawal_intent_script_hash,
    )

  (total_intent_datum_lp_amount == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_intent_datum_lp_usdm_value == convert_lp_to_usdm(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ))?
}

test process_batch_excessive_indices() fail {
  let (total_intent_datum_lp_amount, total_intent_datum_lp_usdm_value) =
    process_batched_withdrawal_intent_validation(
      inputs,
      outputs,
      excessive_indices,
      mock_vault_balance,
      mock_total_lp,
      mock_operator_fee,
      prices,
      mock_withdrawal_intent_script_hash,
    )

  (total_intent_datum_lp_amount == lp_amount_a + lp_amount_b + lp_amount_c)? && (total_intent_datum_lp_usdm_value == convert_lp_to_usdm(
    lp_amount_a,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_b,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ) + convert_lp_to_usdm(
    lp_amount_c,
    mock_total_lp,
    mock_vault_balance,
    mock_operator_fee,
  ))?
}
