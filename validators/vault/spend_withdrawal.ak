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

validator vault(app_oracle: PolicyId, vault_oracle: PolicyId) {
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
    let oracle_datum: VaultOracleDatum =
      get_vault_oracle_datum(inputs, vault_oracle)

    when redeemer is {
      ProcessWithdrawal -> {
        // WithdrawalIntent is burnt
        let mint_purpose = Mint(oracle_datum.l1_withdrawal_intent_script_hash)
        check_mint_redeemer_is_burn_intent(mint_purpose, redeemers)?
      }
      DepositIntoDeltaDeFi -> {
        // Obtain DeltaDeFi's AppOracleDatum
        let app_oracle_datum: AppOracleDatum =
          get_app_oracle_datum(reference_inputs, app_oracle)
        // app_deposit_request_token is minted
        check_any_policy_minted(
          mint,
          app_oracle_datum.app_deposit_request_token,
        )?
      }
      StakeRotation ->
        // Withdrawal Script vault_stake_rotation is validated
        withdrawal_script_validated(
          withdrawals,
          oracle_datum.vault_stake_rotation_script_hash,
        )
      VaultPluggableLogic ->
        // Withdrawal Script pluggable_logic is validated
        withdrawal_script_validated(withdrawals, oracle_datum.pluggable_logic)
    }
  }

  withdraw(_r, _a, self: Transaction) {
    let Transaction { inputs, reference_inputs, extra_signatories, .. } = self

    // Get vault oracle datum from inputs
    let vault_oracle_datum: VaultOracleDatum =
      get_vault_oracle_datum(inputs, vault_oracle)

    // Get app_oracle reference input
    let app_oracle_datum: AppOracleDatum =
      get_app_oracle_datum(reference_inputs, app_oracle)

    // Signed by either operator_key OR operation_key from app_oracle
    let is_operator_signed =
      key_signed(extra_signatories, vault_oracle_datum.operator_key)
    let is_operation_signed =
      key_signed(extra_signatories, app_oracle_datum.operation_key)

    (is_operator_signed || is_operation_signed)?
  }

  else(_) {
    fail
  }
}
