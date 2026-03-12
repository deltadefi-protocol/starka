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

// Vault Datum — merged oracle config + vault state + merkle root
pub type VaultDatum {
  // Config (immutable after creation)
  app_oracle: PolicyId,
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
  // State (mutable)
  total_lp: Int,
  operator_lp: Int,
  vault_cost: Int,
  lp_merkle_root: ByteArray,
  is_active: Bool,
}

// Vault mint redeemer
pub type VaultMintRedeemer {
  CreateVault {
    initial_deposit: MValue,
    initial_lp: Int,
    prices_message: ByteArray,
    signatures: List<ByteArray>,
    initial_lp_proof: Proof,
  }
  CloseVault
}

// Vault spend redeemer
pub type VaultSpendRedeemer {
  ProcessL1Deposit
  ProcessL1Withdrawal
  ProcessL2Deposit
  ProcessL2Withdrawal
  HydraCommit
  HydraDecommit
  Trade
  PluggableLogic
}

// Intent redeemer (shared by all 4 intent validators)
pub type IntentRedeemer {
  MintIntent
  BurnIntent(List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)
  CancelIntent
}

// LP Merkle Patricia Forestry action type
pub type LPMPFAction {
  LPInsert { proof: Proof, new_value: ByteArray }
  LPUpdate { from: ByteArray, to: ByteArray, to_proof: Proof }
  LPDelete { proof: Proof, old_value: ByteArray }
}

// LP Record entry (serialized into MPF values)
pub type LPRecordEntry {
  lp: Int,
  cost: Int,
}

// Price oracle message
pub type Message {
  vault_balance: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  utxo_ref: OutputReference,
}

// Deposit intent datum
pub type DepositIntentDatum {
  lp_address: Address,
  amount: MValue,
}

// Withdrawal intent datum
pub type WithdrawalIntentDatum {
  lp_address: Address,
  amount: Int,
}
