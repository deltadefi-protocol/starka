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
  vault_state_script_hash: ByteArray,
  vault_script_hash: ByteArray,
  deposit_intent_script_hash: ByteArray,
  withdrawal_intent_script_hash: ByteArray,
  lp_record_script_hash: ByteArray,
  pluggable_logic: ByteArray,
  vault_stake_rotation_script_hash: ByteArray,
  operator_key: VerificationKeyHash,
  operator_charge_percentage: Int,
  operator_min_deposit_percentage: Int,
  hydra_node_pub_keys: List<VerificationKey>,
  is_active: Bool,
}

pub type ProcessRedeemer {
  ProcessDeposit
  ProcessWithdrawal
}

// 1 - VaultState

pub type VaultStateDatum {
  app_oracle: PolicyId,
  vault_oracle: PolicyId,
  total_lp: Int,
  operator_lp: Int,
  vault_cost: Int,
}

pub type VaultStateMintRedeemer {
  CreateVault {
    initial_deposit: MValue,
    initial_lp: Int,
    prices_message: ByteArray,
    signatures: List<ByteArray>,
  }
  CloseVault
}

// 2 - Vault
pub type VaultRedeemer {
  WithdrawFund
  PluggableLogic
}

// DepositIntent + WithdrawalIntent
pub type IntentRedeemer {
  MintIntent
  BurnIntent(List<Int>, ByteArray, List<ByteArray>)
}

// 3. DepositIntent
pub type Message {
  vault_balance: Int,
  prices: Pairs<(PolicyId, AssetName), Int>,
  utxo_ref: OutputReference,
}

pub type DepositIntentDatum {
  lp_address: Address,
  amount: MValue,
}

// 4 - WithdrawalIntent

pub type WithdrawalIntentDatum {
  lp_address: Address,
  amount: Int,
}

// 5 - LPRecord

pub type LPRecordDatum {
  address: Address,
  lp: Int,
  cost: Int,
}

pub type MValue =
  Pairs<PolicyId, Pairs<AssetName, Int>>
