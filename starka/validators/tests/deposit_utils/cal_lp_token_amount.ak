use deposit_utils
use utils.{cal_operator_fee}

// a: operator fee = 0
const hwm_lp_value_a = 100

const total_lp_a = 83

const vault_balance_a = 80

const operator_fee_a = cal_operator_fee(vault_balance_a, hwm_lp_value_a, 50)

// a: operator fee > 0

const hwm_lp_value_b = 100

const total_lp_b = 83

const vault_balance_b = 120

const operator_fee_b = cal_operator_fee(vault_balance_b, hwm_lp_value_b, 50)

test cal_a() {
  let cal =
    deposit_utils.cal_lp_token_amount(
      80,
      vault_balance_a,
      total_lp_a,
      operator_fee_a,
    )
  cal == 83 && cal != 82
}

test cal_b() {
  let cal =
    deposit_utils.cal_lp_token_amount(
      110,
      vault_balance_b,
      total_lp_b,
      operator_fee_b,
    )
  (cal == 83)?
}

test cal_c() {
  let cal =
    deposit_utils.cal_lp_token_amount(
      0,
      vault_balance_b,
      total_lp_b,
      operator_fee_b,
    )
  (cal == 0)?
}

test cal_4() {
  let cal = deposit_utils.cal_lp_token_amount(1, 1, 0, operator_fee_a)
  (cal == 1000000)?
}
