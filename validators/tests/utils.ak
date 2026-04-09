use aiken/cbor
use aiken/crypto.{blake2b_224}
use aiken/merkle_patricia_forestry as mpf
use cardano/address.{Address, from_script}
use hydra_dex/types.{
  Account, AppOracleDatum, DexOrderBookDatum, HydraInfo, UserTradeAccount,
  WithdrawalScriptHashes,
} as dd_types
use mocktail.{
  mock_policy_id, mock_pub_key_address, mock_pub_key_hash, mock_script_hash,
  mock_utxo_ref,
}
use types.{
  DepositIntentDatum, L2DepositIntentDatum, L2WithdrawalIntentDatum, MValue,
  SharesRecordEntry, VaultOracleDatum, WithdrawalIntentDatum,
}

// ========== Null hash (empty MPF trie root) ==========

pub const null_hash =
  #"0000000000000000000000000000000000000000000000000000000000000000"

// ========== Keys ==========

pub const mock_operation_key = mock_pub_key_hash(0)

pub const mock_stop_key = mock_pub_key_hash(1)

pub const mock_operator_key = mock_pub_key_hash(10)

// Mock operator inner account (Account type for MPF key computation)
pub const mock_operator_inner_account: Account =
  Account {
    account_id: "operator_0",
    master_key: mock_pub_key_address(10, None).payment_credential,
    operation_key: mock_pub_key_address(10, None).payment_credential,
  }

pub const mock_operator_account: dd_types.UserAccount =
  UserTradeAccount {
    account: mock_operator_inner_account,
    trading_logic: mock_script_hash(10),
  }

// ========== Oracle ==========

pub const mock_app_oracle = mock_policy_id(0)

pub const mock_app_oracle_address = from_script(mock_app_oracle)

pub const mock_app_vault_script_hash = "app_vault_address"

pub const mock_app_deposit_request_token = mock_policy_id(1)

pub const mock_emergency_withdrawal_request_token = mock_policy_id(100)

pub const mock_dex_account_balance_token = mock_policy_id(3)

pub const mock_dex_order_book_token = mock_policy_id(4)

pub const mock_emergency_cancel_order_request_token = mock_policy_id(400)

pub const mock_app_deposit_request_address =
  from_script("app_deposit_request_address")

pub const mock_emergency_withdrawal_request_address =
  from_script("emergency_withdrawal_request_address")

pub const mock_dex_account_balance_address =
  from_script("dex_account_balance_address")

pub const mock_dex_order_book_address = from_script("dex_order_book_address")

pub const mock_emergency_cancel_order_request_address =
  from_script("emergency_cancel_order_request_address")

pub const mock_app_deposit = mock_script_hash(0)

pub const mock_app_withdrawal = mock_script_hash(1)

pub const mock_app_vault_stake_rotation_old = mock_script_hash(111)

pub const mock_emergency_cancel_order = mock_script_hash(700)

pub const mock_withdrawal_script_hashes: WithdrawalScriptHashes =
  WithdrawalScriptHashes {
    app_deposit: mock_app_deposit,
    app_withdrawal: mock_app_withdrawal,
    app_vault_stake_rotation: mock_app_vault_stake_rotation_old,
    emergency_cancel_order: mock_emergency_cancel_order,
  }

// ========== Hydra node keys and signers ==========

pub const mock_node_pub_keys =
  [
    #"8a2447b9e7f1705aa5b2dcb16a7254db089fbac7e462cf6008e9a6dc8a7a6c21",
    #"312803d57366263f9e5310262fb9984f58dbc5602ad5ebdd5725719f4f913ced",
    #"fa357c31b2e47f49d4e0da6eac605a4dc068f4e72fbc56bfef2850e2da1ba3a3",
  ]

pub const mock_hydra_signer_1 =
  blake2b_224(
    #"8a2447b9e7f1705aa5b2dcb16a7254db089fbac7e462cf6008e9a6dc8a7a6c21",
  )

pub const mock_hydra_signer_2 =
  blake2b_224(
    #"312803d57366263f9e5310262fb9984f58dbc5602ad5ebdd5725719f4f913ced",
  )

pub const mock_hydra_signer_3 =
  blake2b_224(
    #"fa357c31b2e47f49d4e0da6eac605a4dc068f4e72fbc56bfef2850e2da1ba3a3",
  )

pub const mock_hydra_signers =
  [mock_hydra_signer_1, mock_hydra_signer_2, mock_hydra_signer_3]

pub const mock_app_oracle_datum: AppOracleDatum =
  AppOracleDatum {
    operation_key: mock_operation_key,
    stop_key: mock_stop_key,
    community_stop_keys: [mock_operation_key, mock_stop_key],
    oracle_nft: mock_app_oracle,
    oracle_address: mock_app_oracle_address,
    app_vault_script_hash: mock_app_vault_script_hash,
    app_deposit_request_token: mock_app_deposit_request_token,
    app_deposit_request_address: mock_app_deposit_request_address,
    dex_account_balance_token: mock_dex_account_balance_token,
    dex_account_balance_address: mock_dex_account_balance_address,
    dex_order_book_token: mock_dex_order_book_token,
    dex_order_book_address: mock_dex_order_book_address,
    emergency_cancel_order_request_token: mock_emergency_cancel_order_request_token,
    emergency_cancel_order_request_address: mock_emergency_cancel_order_request_address,
    emergency_withdrawal_request_token: mock_emergency_withdrawal_request_token,
    emergency_withdrawal_request_address: mock_emergency_withdrawal_request_address,
    all_withdrawal_script_hashes: mock_withdrawal_script_hashes,
    hydra_info: HydraInfo { hydra_signers: mock_hydra_signers },
  }

// ========== Price oracle message and signatures ==========

// Message: vault_equity=2400000000, prices={USDM:1, ADA:2}, utxo_ref=mock_utxo_ref(0,0)
pub const mock_message =
  #"d8799f1a8f0d1800a29f581cc69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913445553444dff019f4040ff02d8799f5820cd82a190d3b4ef95a50bd791882959f541e308adb69b12d022d94a6d9f02bcf000ffff"

pub const mock_signatures =
  [
    #"746bcbe44a67cfec83e98532d32fd10a7aeb93a2f328b2aced147c856d910fe0461614c5fcf90e20427333c7099e71de35a7a08d8e0ececdbeade9776069f102",
    #"d09c37ac69820b7f19e5d2b0def60be06e89b026155b934bd0c3bf8de216c9d377265c14c7e42eb2b9011550ca3aa1825c57ddc999b028eebc5c5a94dbb8710f",
    #"c9c6d6187fa41047e5df0cd59916cd8706a83d368ce2a99aee0e9c67a78c7095f1344d889c2007b788e8f18ad1ee49cd4dfad0488de674a497ef4477494a2e04",
  ]

// ========== Vault NFT and addresses ==========

pub const mock_vault_nft = mock_policy_id(20)

pub const mock_vault_address = from_script(mock_vault_nft)

pub const mock_initial_utxo = mock_utxo_ref(99, 0)

// ========== Intent script hashes ==========

pub const mock_l1_deposit_intent_script_hash = mock_script_hash(11)

pub const mock_l1_withdrawal_intent_script_hash = mock_script_hash(12)

pub const mock_l2_deposit_intent_script_hash = mock_script_hash(13)

pub const mock_l2_withdrawal_intent_script_hash = mock_script_hash(14)

pub const mock_pluggable_logic = mock_script_hash(15)

pub const mock_vault_stake_rotation_script_hash = mock_script_hash(16)

pub const mock_vault_script_hash = mock_script_hash(17)

pub const mock_hydra_user_intent_script_hash = mock_script_hash(50)

pub const mock_hydra_account_script_hash = mock_script_hash(51)

pub const mock_hydra_order_book_script_hash = mock_script_hash(52)

pub const mock_hydra_token_policy_id = mock_policy_id(53)

// ========== Vault state values ==========

pub const mock_total_shares = 3000000000000000

pub const mock_vault_equity = 2400000000

pub const mock_total_deposited = 2000000000

pub const mock_operator_shares = 0

pub const mock_operator_fee_rate_bp = 0

// ========== USDM constants ==========

pub const usdm_policy =
  #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913"

pub const usdm_name = #"5553444d"

// ========== CreateVault test values ==========
// Simple test values: 1000 ADA + 1000 USDM with prices ADA=1, USDM=1
// Total USD value = 1000 + 1000 = 2000 USD = 2_000_000_000 (with 6 decimal precision)
// Genesis rule: initial_shares = total_deposited

pub const mock_create_vault_initial_shares = 2_000_000_000

pub const mock_create_vault_total_deposited = 2_000_000_000

// Simple deposit: 1000 ADA + 1000 USDM
pub const mock_create_vault_deposit_m_value: MValue =
  [
    Pair("", [Pair("", 1_000_000_000)]),
    Pair(usdm_policy, [Pair(usdm_name, 1_000_000_000)]),
  ]

// Placeholder message - TODO: replace with signed message matching above values
// Expected message content: prices={ADA:1, USDM:1}, utxo_ref=mock_utxo_ref(99,0)
pub const mock_create_vault_message: ByteArray = #""

// Placeholder signatures - TODO: replace with real signatures
pub const mock_create_vault_signatures: List<ByteArray> = [#"", #"", #""]

// ========== Vault oracle datum ==========

pub const mock_vault_oracle_datum: VaultOracleDatum =
  VaultOracleDatum {
    app_oracle: mock_app_oracle,
    vault_script_hash: mock_vault_script_hash,
    l1_deposit_intent_script_hash: mock_l1_deposit_intent_script_hash,
    l1_withdrawal_intent_script_hash: mock_l1_withdrawal_intent_script_hash,
    l2_deposit_intent_script_hash: mock_l2_deposit_intent_script_hash,
    l2_withdrawal_intent_script_hash: mock_l2_withdrawal_intent_script_hash,
    pluggable_logic: mock_pluggable_logic,
    vault_stake_rotation_script_hash: mock_vault_stake_rotation_script_hash,
    operator_account: mock_operator_account,
    operator_fee_rate_bp: mock_operator_fee_rate_bp,
    operator_min_deposit_rate_bp: 10,
    hydra_node_pub_keys: mock_node_pub_keys,
    is_active: True,
    total_shares: mock_total_shares,
    operator_shares: mock_operator_shares,
    total_deposited: mock_total_deposited,
    shares_merkle_root: null_hash,
    total_fee_share_collected: 0,
  }

// ========== DexOrderBook datum ==========

pub const mock_dex_order_book_datum: DexOrderBookDatum =
  DexOrderBookDatum {
    operation_key: mock_operation_key,
    stop_key: mock_operation_key,
    fee_account: UserTradeAccount {
      account: Account {
        account_id: "fee_account",
        master_key: from_script(mock_hydra_user_intent_script_hash).payment_credential,
        operation_key: from_script(mock_hydra_user_intent_script_hash).payment_credential,
      },
      trading_logic: mock_hydra_user_intent_script_hash,
    },
    limit_orders_merkle_root: null_hash,
    dex_account_balance_token: mock_dex_account_balance_token,
    dex_account_balance_address: mock_dex_account_balance_address,
    dex_order_book_token: mock_dex_order_book_token,
    dex_order_book_address: mock_dex_order_book_address,
    hydra_user_intent_script_hash: mock_hydra_user_intent_script_hash,
    hydra_account_script_hash: mock_hydra_account_script_hash,
    hydra_order_book_script_hash: mock_hydra_order_book_script_hash,
    hydra_token_policy_id: mock_hydra_token_policy_id,
  }

// ========== Deposit / Withdrawal intent data ==========

pub const mock_deposit_m_value: MValue =
  [
    Pair("", [Pair("", 1749190790)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 143533706)],
    ),
  ]

pub const mock_l2_deposit_m_value: MValue =
  [
    Pair("", [Pair("", 1749190790)]),
    Pair(
      #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
      [Pair(#"5553444d", 143533706)],
    ),
  ]

// Mock user account for intents (inner Account)
pub const mock_user_account: Account =
  Account {
    account_id: "user_0",
    master_key: mock_pub_key_address(0, None).payment_credential,
    operation_key: mock_pub_key_address(0, None).payment_credential,
  }

// Mock user trade account (UserAccount wrapper for intent datums)
pub const mock_user_trade_account: dd_types.UserAccount =
  UserTradeAccount {
    account: mock_user_account,
    trading_logic: mock_script_hash(0),
  }

// Derive address from mock_user_account's master_key (for MPF key computation)
pub fn mock_user_address() -> Address {
  Address {
    payment_credential: mock_user_account.master_key,
    stake_credential: None,
  }
}

pub const mock_deposit_intent_datum =
  DepositIntentDatum {
    depositor: mock_user_trade_account,
    deposit_amount: mock_deposit_m_value,
  }

pub const mock_withdrawal_intent_datum =
  WithdrawalIntentDatum {
    withdrawer: mock_user_trade_account,
    shares_to_redeem: 1000000,
  }

pub const mock_l2_deposit_intent_datum =
  L2DepositIntentDatum {
    vault_oracle_nft: mock_vault_nft,
    depositor: mock_user_trade_account,
    deposit_amount: mock_l2_deposit_m_value,
  }

pub const mock_l2_withdrawal_intent_datum =
  L2WithdrawalIntentDatum {
    vault_oracle_nft: mock_vault_nft,
    withdrawer: mock_user_trade_account,
    shares_to_redeem: 1000000,
  }

// ========== MPF helper ==========

pub fn compute_mpf_root_single_insert(
  account: Account,
  shares: Int,
  total_deposited: Int,
) -> ByteArray {
  let mpf_key = cbor.serialise(account)
  let entry = SharesRecordEntry { shares, total_deposited }
  let mpf_value = cbor.serialise(entry)
  mpf.root(mpf.insert(mpf.empty, mpf_key, mpf_value, []))
}
