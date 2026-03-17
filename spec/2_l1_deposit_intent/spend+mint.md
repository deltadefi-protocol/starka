# Specification - L1 Deposit Intent

L1 deposit intents allow users to deposit funds to the Trust Me Bro vault on L1. The vault then performs a regular deposit (AppDeposit) to AppVault, increasing the vault's account balance.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `depositor`: UserAccount - receiver of LP shares (contains Account with account_id, master_key, operation_key)
- `deposit_amount`: `MValue` - value being deposited

## User Action - Spend

1. Process Intent
   - `L1DepositIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`
   - Deposit amount > 0
   - The net deposit value sent to `L1DepositIntent` address equals the datum amount
   - No vault reference needed (user creates intent independently)

2. BurnIntent - Redeemer `BurnIntent (List<Int>, ByteArray, List<ByteArray>, List<SharesMPFAction>)`
   - **Signed by `operation_key` from `app_oracle`**
   - `L1DepositIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_shares += sum(cal_shares)` across all intents
     - `total_deposited += sum(intent_usd_value)` across all intents
     - `shares_merkle_root` updated
     - All other datum fields unchanged
   - Vault UTxO spent (funds added to vault)
   - Vault performs AppDeposit to AppVault (increases vault's account balance)
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - Shares Merkle root transition:
     - For each deposit intent (chained sequentially):
       - Calculate `cal_shares = intent_usd_value * total_shares / vault_equity` (round DOWN)
       - **New depositor** (`SharesInsert { proof }`): Compute and insert `SharesRecordEntry { shares: cal_shares, total_deposited: intent_usd_value }`
       - **Existing depositor** (`SharesUpdate { from, to_proof }`): Compute `new_entry.shares = old_entry.shares + cal_shares` and `new_entry.total_deposited = old_entry.total_deposited + intent_usd_value`
     - Note: `new_value`/`to` are computed from shares + total_deposited, not passed in redeemer
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`
   - `L1DepositIntent` token is burnt
   - The intent UTxO value returned to depositor (refund)
   - Signed by the depositor
   - No vault interaction required

## Fund Flow

```
User funds → L1DepositIntent → Vault → AppVault (regular deposit)
                                ↓
                        Vault's account balance increases
```

## Validation Rules (ref: vault-spec 3.4)

1. `deposit_amount > 0` (non-empty MValue)
2. Deposit value actually transferred to vault
3. `shares_minted` computed correctly: `shares = usd_value * total_shares / vault_equity`
4. `new_total_shares = old_total_shares + shares_minted`
5. `new_total_deposited = old_total_deposited + usd_value`
6. Depositor shares record updated correctly in merkle tree

> **Asset Flexibility**: Script accepts ANY asset. Backend restricts accepted assets (e.g., USDC only). Scripts should never change; backend rules can evolve.

## Notes

- Processed on L1 (before HydraCommit)
- User gets shares in the Trust Me Bro vault
- Vault acts as a normal user doing AppDeposit to main system
