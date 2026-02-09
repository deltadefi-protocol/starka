use aiken/crypto.{VerificationKey, VerificationKeyHash}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference}

// Mint Redeemer

pub type MintPolarity {
  RMint
  RBurn
}

// 0 - VaultOracle

pub type VaultOracleDatum {
  app_oracle: PolicyId,
  pluggable_logic: ByteArray,
  node_pub_key: List<VerificationKey>,
  total_lp: Int,
  hwm_lp_value: Int,
  operator_charge_percentage: Int,
  operator_key: VerificationKeyHash,
  vault_cost: Int,
  vault_script_hash: ByteArray,
  deposit_intent_script_hash: ByteArray,
  withdrawal_intent_script_hash: ByteArray,
  lp_token: PolicyId,
}

pub type ProcessRedeemer {
  ProcessDeposit
  ProcessWithdrawal
}

// 1 - Vault
pub type VaultRedeemer {
  WithdrawFund
  PluggableLogic
}

// DepositIntent + WithdrawalIntent
pub type IntentRedeemer {
  MintIntent
  BurnIntent(List<Int>, ByteArray, List<ByteArray>)
}

// 2. DepositIntent
pub type Message {
  vault_balance: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  utxo_ref: OutputReference,
}

pub type DepositIntentDatum {
  lp_address: Address,
  amount: MValue,
}

// 3 - WithdrawalIntent

pub type WithdrawalIntentDatum {
  lp_address: Address,
  amount: Int,
}

// 4 - LPToken

pub type MValue =
  Pairs<PolicyId, Pairs<AssetName, Int>>
