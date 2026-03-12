# Specification - Vault

The Vault UTxO holds the LP funds. It stays on L1 and is NOT committed to Hydra. The vault is treated as a **normal user** in the main DeltaDefi system - it has its own account balance in DexAccountBalance merkle tree.

## Parameter

- `vault_oracle_nft`: PolicyId (links to the Vault Oracle)

## Datum

- `None` (funds only, no state)

## User Action - Spend

1. ProcessL1Deposit

   - `L1DepositIntent` token is burnt with `BurnIntent` redeemer
   - User funds added to Vault
   - Vault performs regular deposit to AppVault (increases vault's account balance)

2. ProcessL1Withdrawal

   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - Vault performs regular withdrawal (HydraAccount withdrawal) in L2
   - User receives funds from Vault

3. PluggableLogic

   - Withdrawal Script `pluggable_logic` (from Oracle datum) is validated

## Notes

- Vault acts as a normal user in the main DeltaDefi system
- L1 Deposit: User → Vault → Vault does AppDeposit → Vault's account balance increases
- L1 Withdrawal: Vault does HydraWithdrawal → Vault → User
- L2 Deposit/Withdrawal: Account balance transfers between user and vault (handled by Oracle)
