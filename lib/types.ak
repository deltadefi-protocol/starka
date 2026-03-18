use aiken/crypto.{VerificationKey}
use aiken/merkle_patricia_forestry.{Proof}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference}
use hydra_dex/types.{TokenMap, UserAccount} as dd_types

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
  operator_account: UserAccount,
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
  MintVault
  CloseVault
}

// Vault Oracle spend redeemer
// Note: L2InitialDeposit is handled by HydraAccount validator (ProcessVaultDeposit with total_shares == 0)
pub type VaultOracleSpendRedeemer {
  L1InitialDeposit {
    depositor: UserAccount,
    initial_deposit: MValue,
    prices_message: ByteArray,
    signatures: List<ByteArray>,
    initial_shares_proof: Proof,
  }
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

// L1 Intent redeemer (with batch processing params)
pub type IntentRedeemerL1 {
  MintIntent
  BurnIntent(List<Int>, ByteArray, List<ByteArray>, List<SharesMPFAction>)
  CancelIntent
}

// L2 Intent redeemer (simplified - main logic in hydra_account/core.ak)
pub type IntentRedeemerL2 {
  MintIntentL2
  BurnIntentL2
  CancelIntentL2
}

// Shares Merkle Patricia Forestry action type
// Note: new_value/to are computed from shares + total_deposited, not passed in redeemer
pub type SharesMPFAction {
  SharesInsert { proof: Proof }
  SharesUpdate { from: ByteArray, to_proof: Proof }
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
  depositor: UserAccount,
  deposit_amount: MValue,
}

// L2 Deposit intent datum — no value stored, only intent token
pub type L2DepositIntentDatum {
  vault_oracle_nft: PolicyId,
  depositor: UserAccount,
  deposit_amount: MValue,
}

// Withdrawal intent datum
pub type WithdrawalIntentDatum {
  withdrawer: UserAccount,
  shares_to_redeem: Int,
}

// L2 Withdrawal intent datum — no value stored, only intent token
pub type L2WithdrawalIntentDatum {
  vault_oracle_nft: PolicyId,
  withdrawer: UserAccount,
  shares_to_redeem: Int,
}

pub type HydraAccountOperation {
  ProcessWithdrawalHydraAccount
  ProcessCancelWithdrawal
  ProcessSameAccountTransferal
  ProcessTransferal
  ProcessCombineUtxosAtClose
  ProcessSplitUtxosAtOpen
  ProcessVaultDeposit(ByteArray, List<ByteArray>, TokenMap, SharesMPFAction)
  ProcessVaultWithdrawal(
    ByteArray,
    List<ByteArray>,
    TokenMap,
    SharesMPFAction,
    SharesMPFAction,
  )
}
