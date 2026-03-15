# Specification - L2 Deposit Intent

L2 deposit intents are created and processed inside the Hydra head. User transfers balance from their Account UTxO to the vault to receive LP shares.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `depositor`: Address - receiver of LP shares
- `deposit_amount`: `MValue` - value being deposited (hydra token representation)

## User Action - Spend

1. Process Intent
   - `L2DepositIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`
   - Deposit amount > 0
   - Intent UTxO only contains the intent token (no deposit value)
   - Tokens are stored in user's Account UTxO

2. BurnIntent - Redeemer `BurnIntent (List<Int>, ByteArray, List<ByteArray>, List<SharesMPFAction>)`
   - **Signed by `operation_key` from `app_oracle`**
   - `L2DepositIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_shares += sum(cal_shares)` across all intents
     - `total_deposited += sum(intent_usd_value)` across all intents
     - `shares_merkle_root` updated (see Shares Merkle transition below)
     - All other datum fields unchanged
   - Balance transferred from user's Account UTxO to vault (via TransferIntent)
   - **Each deposit intent's `deposit_amount` must equal the corresponding TransferIntent's `amount_l2` (in USD value)**
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - Shares Merkle root transition:
     - For each deposit intent (chained sequentially):
       - Calculate `cal_shares = intent_usd_value * total_shares / vault_equity` (round DOWN)
       - **New depositor** (`SharesInsert`): Insert `SharesRecordEntry { shares: cal_shares, total_deposited: intent_usd_value }`
       - **Existing depositor** (`SharesUpdate`): Verify `new_entry.shares == old_entry.shares + cal_shares` and `new_entry.total_deposited == old_entry.total_deposited + intent_usd_value`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`
   - `L2DepositIntent` token is burnt
   - **Signed by `operation_key` from `app_oracle`**
   - Vault Oracle input required (to get `app_oracle` reference)
   - No value refund needed (tokens are in Account UTxO, not intent)

## Balance Flow

```
User's Account UTxO → (TransferIntent) → Vault's Account UTxO
```

## Validation Rules (ref: vault-spec 3.4)

1. `deposit_amount > 0` (non-empty MValue)
2. Balance transferred from user's Account to vault's Account (via TransferIntent)
3. **Each `deposit_amount` in intent datum must equal the corresponding `amount_l2` in TransferIntent (in USD value)** (prevents claiming more shares than actually transferred)
4. `shares_minted` computed correctly: `shares = usd_value * total_shares / vault_equity`
5. `new_total_shares = old_total_shares + shares_minted`
6. `new_total_deposited = old_total_deposited + usd_value`
7. Depositor shares record updated correctly in merkle tree

> **Asset Flexibility**: Script accepts ANY asset. Backend restricts accepted assets (e.g., USDC only). Scripts should never change; backend rules can evolve.

## Notes

- Deployed inside the Hydra head
- Intent UTxO only holds the intent token (tokens are stored in Account UTxOs)
- Vault Oracle is the only Starka UTxO in Hydra (funds stay in Vault on L1)
- User must have sufficient balance in their Account UTxO (from prior regular deposit)
- Balance transfer uses HydraAccount TransferIntent mechanism
- Vault is treated as a normal user with its own Account UTxO
