use deposit_utils.{combine_m_value}
use types.{MValue}

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

const m_value_a_and_b =
  [
    Pair("", [Pair("", 300)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 300)],
    ),
  ]

const m_value_a_and_b_wrong =
  [
    Pair("", [Pair("", 300)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 301)],
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

const m_value_a_and_b_and_c =
  [
    Pair("", [Pair("", 600)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair("", 300), Pair(#"5553444d", 600)],
    ),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c999",
      [Pair(#"5553444d", 300)],
    ),
  ]

const empty_m_value: MValue = []

test combine_a_and_b() {
  combine_m_value(m_value_a, m_value_b) == m_value_a_and_b
}

test combine_a_and_b_wrong() {
  combine_m_value(m_value_a, m_value_b) != m_value_a_and_b_wrong
}

test combine_a_and_b_and_c() {
  (combine_m_value(m_value_a_and_b, m_value_c) == m_value_a_and_b_and_c)?
}

test combine_empty_and_a() {
  combine_m_value(empty_m_value, m_value_a) == m_value_a
}
