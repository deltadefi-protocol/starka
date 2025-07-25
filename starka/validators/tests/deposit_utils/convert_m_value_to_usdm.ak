use deposit_utils.{convert_m_value_to_usd}
use types.{MValue}

const prices: Pairs<ByteArray, Int> =
  [
    Pair(#"", 2),
    Pair(#"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c9135553444d", 1),
  ]

const empty_m_value: MValue = []

const m_value_a =
  [
    Pair("", [Pair("", 100)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 100)],
    ),
  ]

const m_value_b =
  [
    Pair("", [Pair("", 200)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 200)],
    ),
  ]

const m_value_c =
  [
    Pair("", [Pair("", 300)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair("", 300), Pair(#"5553444d", 300)],
    ),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c999",
      [Pair(#"5553444d", 300)],
    ),
  ]

const m_value_a_in_usd = 300

const m_value_b_in_usd = 600

test convert_m_value_a() {
  convert_m_value_to_usd(m_value_a, prices) == m_value_a_in_usd
}

test convert_m_value_b() {
  convert_m_value_to_usd(m_value_b, prices) == m_value_b_in_usd
}

test convert_empty_m_value() {
  convert_m_value_to_usd(empty_m_value, prices) == 0
}

test convert_m_value_c() fail {
  convert_m_value_to_usd(m_value_c, prices) == 0
}
