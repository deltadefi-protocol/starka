use aiken/crypto.{VerificationKey, VerificationKeyHash}
use aiken/merkle_patricia_forestry.{Proof}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference}

// Shared multi-asset value type
pub type MValue =
  Pairs<PolicyId, Pairs<AssetName, Int>>

// Mint Redeemer (simple mint/burn for oracle NFT etc.)
pub type MintPolarity {
  RMint
  RBurn
}

// Vault Oracle Datum — holds config + state, commits to Hydra
pub type VaultOracleDatum {
  // Config (all updatable via UpdateConfig)
  app_oracle: PolicyId,
  vault_script_hash: ByteArray,
  l1_deposit_intent_script_hash: ByteArray,
  l1_withdrawal_intent_script_hash: ByteArray,
  l2_deposit_intent_script_hash: ByteArray,
  l2_withdrawal_intent_script_hash: ByteArray,
  pluggable_logic: ByteArray,
  vault_stake_rotation_script_hash: ByteArray,
  operator_key: VerificationKeyHash,
  operator_charge_percentage: Int,
  operator_min_deposit_percentage: Int,
  hydra_node_pub_keys: List<VerificationKey>,
  is_active: Bool,
  // State (mutable)
  total_shares: Int,
  operator_shares: Int,
  total_deposited: Int,
  shares_merkle_root: ByteArray,
  total_fee_collected: Int,
}

// Vault Oracle mint redeemer
pub type VaultOracleMintRedeemer {
  CreateVault {
    initial_deposit: MValue,
    initial_shares: Int,
    prices_message: ByteArray,
    signatures: List<ByteArray>,
    initial_shares_proof: Proof,
  }
  CloseVault
}

// Vault Oracle spend redeemer
pub type VaultOracleSpendRedeemer {
  ProcessL1Deposit
  ProcessL1Withdrawal
  ProcessL2Deposit
  ProcessL2Withdrawal
  HydraCommit
  HydraDecommit
  PluggableLogic
  UpdateConfig
}

// Vault spend redeemer — fund management validator
pub type VaultSpendRedeemer {
  ProcessWithdrawal
  DepositIntoDeltaDeFi
  StakeRotation
  VaultPluggableLogic
}

// Intent redeemer (shared by all 4 intent validators)
pub type IntentRedeemer {
  MintIntent
  BurnIntent(List<Int>, ByteArray, List<ByteArray>, List<SharesMPFAction>)
  CancelIntent
}

// Shares Merkle Patricia Forestry action type
pub type SharesMPFAction {
  SharesInsert { proof: Proof, new_value: ByteArray }
  SharesUpdate { from: ByteArray, to: ByteArray, to_proof: Proof }
  SharesDelete { proof: Proof, old_value: ByteArray }
}

// Shares Record entry (serialized into MPF values)
pub type SharesRecordEntry {
  shares: Int,
  total_deposited: Int,
}

// Price oracle message
pub type Message {
  vault_equity: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  utxo_ref: OutputReference,
}

// Deposit intent datum
pub type DepositIntentDatum {
  depositor: Address,
  deposit_amount: MValue,
}

// L2 Deposit intent datum — no value stored, only intent token
pub type L2DepositIntentDatum {
  depositor: Address,
  deposit_amount: MValue,
}

// Withdrawal intent datum
pub type WithdrawalIntentDatum {
  withdrawer: Address,
  shares_to_redeem: Int,
}

// L2 Withdrawal intent datum — no value stored, only intent token
pub type L2WithdrawalIntentDatum {
  withdrawer: Address,
  shares_to_redeem: Int,
}
