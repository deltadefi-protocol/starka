use aiken/crypto.{ScriptHash, VerificationKey, VerificationKeyHash}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference}

// Mint Redeemer

pub type MintPolarity {
  RMint
  RBurn
}

// AppOracle

pub type WithdrawalScriptHashes {
  app_deposit: ScriptHash,
  app_withdrawal: ScriptHash,
  emergency_cancel_order: ScriptHash,
}

pub type AppOracleDatum {
  operation_key: VerificationKeyHash,
  stop_key: VerificationKeyHash,
  oracle_nft: PolicyId,
  oracle_address: Address,
  app_vault_address: Address,
  app_deposit_request_token: PolicyId,
  app_deposit_request_address: Address,
  dex_account_balance_token: PolicyId,
  dex_account_balance_address: Address,
  dex_order_book_token: PolicyId,
  dex_order_book_address: Address,
  emergency_cancel_order_request_token: PolicyId,
  emergency_cancel_order_request_address: Address,
  emergency_withdrawal_request_token: PolicyId,
  emergency_withdrawal_request_address: Address,
  all_withdrawal_script_hashes: WithdrawalScriptHashes,
  hydra_info: HydraInfo,
}

pub type HydraInfo {
  hydra_initial_hash: ScriptHash,
  hydra_signers: List<VerificationKeyHash>,
}

// 0 - VaultOracle

pub type VaultOracleDatum {
  app_oracle: PolicyId,
  pluggable_logic: ByteArray,
  node_pub_key: List<VerificationKey>,
  total_lp: Int,
  hwm_lp_value: Int,
  operator_charge: Int,
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

// 2 - DepositIntent
pub type IntentRedeemer {
  MintIntent
  BurnIntent(List<Int>, ByteArray, List<ByteArray>)
}

pub type Message {
  vault_balance: Int,
  prices: Pairs<ByteArray, Int>,
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
