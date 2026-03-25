# Specification - L2 Deposit Intent

L2 deposit intents are created and processed inside the Hydra head. User transfers balance from their Account UTxO to the vault to receive LP shares.

## Parameter

- `vault_oracle_nft`: PolicyId
- `dex_oracle_nft`: PolicyId

## Datum

- `vault_oracle_nft`: PolicyId - must match validator parameter
- `depositor`: UserAccount - user account receiving LP shares (contains Account with account_id, master_key, operation_key)
- `deposit_amount`: `MValue` - value being deposited (hydra token representation)

## User Action - Spend

1. Process Intent
   - `L2DepositIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`
   - **Signed by depositor master_key** (from datum `depositor.master_key`)
   - `vault_oracle_nft` in datum matches validator parameter
   - Deposit amount > 0 (non-empty `deposit_amount`)
   - Intent UTxO only contains the intent token (no deposit value)
   - Tokens are stored in user's Account UTxO

2. BurnIntent - Redeemer `BurnIntent`
   - `L2DepositIntent` is burnt (exactly 1)
   - Withdrawal script validated with `ProcessVaultDeposit` redeemer
   - Main validation logic in `hydra_account/core.ak`

3. CancelIntent - Redeemer `CancelIntent`
   - **Signed by `operation_key` from DexOrderBook**
   - DexOrderBook referenced via `dex_oracle_nft` parameter
   - No intent tokens in outputs (batch burn supported)
   - No value refund needed (tokens are in Account UTxO, not intent)

## ProcessVaultDeposit (hydra_account/core.ak)

The main deposit logic is handled in the hydra_account withdrawal script:

**Inputs:**
- Vault Oracle (with `vault_oracle_nft`)
- L2 Deposit Intent (single intent, no batching)
- Depositor's Account UTxO
- Vault's Account UTxO

**Outputs:**
- Vault Oracle (updated)
- Depositor's Account UTxO (balance decreased)
- Vault's Account UTxO (balance increased)

**Validation:**
1. **Signed by `operation_key` from `app_oracle`**
2. Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - **Price format**: `Pairs<(PolicyId, AssetName), (Int, Int)>` where tuple is `(price, scale)`
   - **USD calculation**: `usd_value = Σ(amount * price / 10^scale)` for each asset
3. Calculate shares:
   - **Initial deposit** (`total_shares == 0`): `cal_shares = intent_usd_value` (share price = 1.0)
   - **Regular deposit**: `cal_shares = intent_usd_value * total_shares / vault_equity` (round DOWN)
4. Update Vault Oracle datum:
   - `total_shares += cal_shares`
   - `total_deposited += intent_usd_value`
   - `shares_merkle_root` updated via MPF action
5. Update Account balances:
   - Depositor Account: `balance -= deposit_amount`
   - Vault Account: `balance += deposit_amount`
6. Shares Merkle transition:
   - **New depositor** (`SharesInsert { proof }`): Compute and insert `SharesRecordEntry { shares: cal_shares, total_deposited: intent_usd_value }`
   - **Existing depositor** (`SharesUpdate { from, to_proof }`): Compute `new_entry.shares = old_entry.shares + cal_shares` and `new_entry.total_deposited = old_entry.total_deposited + intent_usd_value`
   - Note: `new_value`/`to` are computed, not passed in redeemer

## Balance Flow

```
User's Account UTxO → (ProcessVaultDeposit) → Vault's Account UTxO
```

## Signing Summary

| Action | Signed By |
|--------|-----------|
| MintIntent | **User** (depositor.master_key) |
| BurnIntent | `operation_key` (via ProcessVaultDeposit) |
| CancelIntent | `operation_key` |

## Validation Rules (ref: vault-spec 3.4)

1. `deposit_amount > 0` (non-empty MValue)
2. Balance transferred from user's Account to vault's Account (direct update)
3. `shares_minted` computed correctly:
   - Initial deposit (`total_shares == 0`): `shares = usd_value`
   - Regular deposit: `shares = usd_value * total_shares / vault_equity`
4. `new_total_shares = old_total_shares + shares_minted`
5. `new_total_deposited = old_total_deposited + usd_value`
6. Depositor shares record updated correctly in merkle tree

> **Asset Flexibility**: Script accepts ANY asset. Backend restricts accepted assets (e.g., USDC only). Scripts should never change; backend rules can evolve.

## Notes

- Deployed inside the Hydra head
- Intent UTxO only holds the intent token (tokens are stored in Account UTxOs)
- Vault Oracle is the only Starka UTxO in Hydra (funds stay in Vault on L1)
- User must have sufficient balance in their Account UTxO (from prior regular deposit)
- **No TransferIntent required** - direct account balance update via ProcessVaultDeposit
- **No batching** - single intent per transaction
- Vault is treated as a normal user with its own Account UTxO
