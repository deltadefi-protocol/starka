use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, OutputReference, Transaction}
use cocktail.{key_signed}
use hydra_dex/types.{AppOracleDatum} as dd_types
use types.{
  DepositIntoDeltaDeFi, ProcessWithdrawal, StakeRotation, VaultOracleDatum,
  VaultPluggableLogic, VaultSpendRedeemer,
}
use utils.{
  check_any_policy_minted, check_mint_redeemer_is_burn_intent,
  get_app_oracle_datum, get_vault_oracle_datum, withdrawal_script_validated,
}

validator vault(vault_oracle: PolicyId) {
  spend(
    _datum,
    redeemer: VaultSpendRedeemer,
    _input: OutputReference,
    self: Transaction,
  ) {
    let Transaction {
      inputs,
      reference_inputs,
      redeemers,
      withdrawals,
      mint,
      ..
    } = self

    // Get vault oracle datum from inputs
    when redeemer is {
      ProcessWithdrawal -> {
        let vault_oracle_datum: VaultOracleDatum =
          get_vault_oracle_datum(inputs, vault_oracle)

        let VaultOracleDatum { l1_withdrawal_intent_script_hash, .. } =
          vault_oracle_datum
        // WithdrawalIntent is burnt
        let mint_purpose = Mint(l1_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      DepositIntoDeltaDeFi -> {
        let vault_oracle_datum: VaultOracleDatum =
          get_vault_oracle_datum(reference_inputs, vault_oracle)

        let VaultOracleDatum { app_oracle, .. } = vault_oracle_datum
        // Obtain DeltaDeFi's AppOracleDatum
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, app_oracle)
        // app_deposit_request_token is minted
        check_any_policy_minted(
          mint,
          app_oracle_datum.app_deposit_request_token,
        )?
      }
      StakeRotation -> {
        // Withdrawal Script vault_stake_rotation is validated
        let vault_oracle_datum: VaultOracleDatum =
          get_vault_oracle_datum(reference_inputs, vault_oracle)

        let VaultOracleDatum { vault_stake_rotation_script_hash, .. } =
          vault_oracle_datum
        withdrawal_script_validated(
          withdrawals,
          vault_stake_rotation_script_hash,
        )
      }
      VaultPluggableLogic -> {
        // Withdrawal Script pluggable_logic is validated
        let vault_oracle_datum: VaultOracleDatum =
          get_vault_oracle_datum(reference_inputs, vault_oracle)

        let VaultOracleDatum { pluggable_logic, .. } = vault_oracle_datum
        withdrawal_script_validated(withdrawals, pluggable_logic)
      }
    }
  }

  withdraw(_r, _a, self: Transaction) {
    let Transaction { reference_inputs, extra_signatories, .. } = self

    // Get vault oracle datum from inputs
    let vault_oracle_datum: VaultOracleDatum =
      get_vault_oracle_datum(reference_inputs, vault_oracle)

    let VaultOracleDatum { app_oracle, operator_key, .. } = vault_oracle_datum
    // Get app_oracle reference input
    let app_oracle_datum: AppOracleDatum =
      get_app_oracle_datum(reference_inputs, app_oracle)

    // Signed by either operator_key OR operation_key from app_oracle
    let is_operator_signed = key_signed(extra_signatories, operator_key)
    let is_operation_signed =
      key_signed(extra_signatories, app_oracle_datum.operation_key)

    (is_operator_signed || is_operation_signed)?
  }

  else(_) {
    fail
  }
}
