use cardano/assets.{add, from_asset}
use tests/withdraw_utils/process_batch.{prices}
use withdraw_utils.{check_output_value_equal_to_lp_usd_value}

const output_value_a =
  from_asset(
    #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
    #"5553444d",
    1000000,
  )
    |> add(#"", #"", 2000000)

const output_value_b =
  from_asset(
    #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
    #"5553444d",
    2000000,
  )
    |> add(#"", #"", 1000000)

const output_value_c =
  from_asset(
    #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
    #"5553444d",
    2000000,
  )
    |> add(
        #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c999",
        #"",
        1000000,
      )

const lp_usd_value_a = 5000000

const lp_usd_value_b = 4000000

const lp_usd_value_c = 4000000

test check_output_value_a() {
  check_output_value_equal_to_lp_usd_value(
    output_value_a,
    lp_usd_value_a,
    prices,
  )
}

test check_output_value_b() {
  check_output_value_equal_to_lp_usd_value(
    output_value_b,
    lp_usd_value_b,
    prices,
  )
}

test check_output_value_c() fail {
  check_output_value_equal_to_lp_usd_value(
    output_value_c,
    lp_usd_value_c,
    prices,
  )
}
