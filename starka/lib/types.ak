use aiken/crypto.{VerificationKey, VerificationKeyHash}
use cardano/assets.{PolicyId}

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
  operator_charge: Int,
  operator_key: VerificationKeyHash,
  vault_cost: Int,
  emergency_cancel_order_request_token: PolicyId,
  emergency_cancel_order_request_address: Address,
  emergency_withdrawal_request_token: PolicyId,
  emergency_withdrawal_request_address: Address,
}

pub type VaultOracleRedeemer {
  ProcessDeposit
  ProcessWithdrawal
}
