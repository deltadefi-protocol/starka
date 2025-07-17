use aiken/cbor
use cardano/address.{Script, VerificationKey, from_script}
use cardano/assets.{Value, from_asset}
use mocktail.{
  mock_policy_id, mock_pub_key_hash, mock_script_hash,
  mock_verfication_key_credential,
}
use mocktail/virgin_address.{mock_script_address}
use types.{AppOracleDatum, HydraInfo, WithdrawalScriptHashes}

pub const mock_operation_key = mock_pub_key_hash(0)

pub const mock_stop_key = mock_pub_key_hash(1)

pub const mock_app_oracle = mock_policy_id(0)

pub const mock_app_deposit_request_token = mock_policy_id(1)

pub const mock_emergency_withdrawal_request_token = mock_policy_id(100)

pub const mock_dex_account_balance_token = mock_policy_id(3)

pub const mock_dex_order_book_token = mock_policy_id(4)

pub const mock_emergency_cancel_order_request_token = mock_policy_id(400)

pub const mock_app_oracle_address = from_script("app_oracle_address")

pub const mock_app_vault_address = from_script("app_vault_address")

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

pub const mock_emergency_cancel_order = mock_script_hash(700)

pub const mock_withdrawal_script_hashes: WithdrawalScriptHashes =
  WithdrawalScriptHashes {
    app_deposit: mock_app_deposit,
    app_withdrawal: mock_app_withdrawal,
    emergency_cancel_order: mock_emergency_cancel_order,
  }

pub const mock_hydra_initial_hash = mock_script_hash(999)

pub const mock_hydra_script_address = mock_script_address(999, None)

pub const mock_hydra_signer_1 = mock_pub_key_hash(100)

pub const mock_hydra_signer_2 = mock_pub_key_hash(200)

pub const mock_hydra_signer_3 = mock_pub_key_hash(300)

pub const mock_hydra_signers =
  [mock_hydra_signer_1, mock_hydra_signer_2, mock_hydra_signer_3]

pub const mock_input_oracle_datum: AppOracleDatum =
  AppOracleDatum {
    operation_key: mock_operation_key,
    stop_key: mock_stop_key,
    oracle_nft: mock_app_oracle,
    oracle_address: mock_app_oracle_address,
    app_vault_address: mock_app_vault_address,
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
    hydra_info: HydraInfo {
      hydra_initial_hash: mock_hydra_initial_hash,
      hydra_signers: mock_hydra_signers,
    },
  }

pub const mock_vault_oracle_datum: VaultOracleDatum =
  VaultOracleDatum { app_oracle: mock_app_oracle }
