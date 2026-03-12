# Specification - L1 Deposit Intent

L1 deposit intents allow users to deposit funds to the Trust Me Bro vault on L1. The vault then performs a regular deposit (AppDeposit) to AppVault, increasing the vault's account balance.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `lp_address`: Address - receiver of LP
- `amount`: `MValue` - deposit amount

## User Action - Spend

1. Process Intent

   - `L1DepositIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`

   - Deposit amount > 0
   - The net deposit value sent to `L1DepositIntent` address equals the datum amount
   - No vault reference needed (user creates intent independently)

2. BurnIntent - Redeemer `BurnIntent (List<Int>, List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L1DepositIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_lp += sum(cal_lp)` across all intents
     - `vault_cost += sum(intent_usd_value)` across all intents
     - `lp_merkle_root` updated
     - All other datum fields unchanged
   - Vault UTxO spent (funds added to vault)
   - Vault performs AppDeposit to AppVault (increases vault's account balance)
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - LP Merkle root transition:
     - For each deposit intent (chained sequentially):
       - Calculate `cal_lp = intent_usd_value * total_lp / vault_balance` (round DOWN)
       - **New depositor** (`LPInsert`): Insert `LPRecordEntry { lp: cal_lp, cost: intent_usd_value }`
       - **Existing depositor** (`LPUpdate`): Verify `new_entry.lp == old_entry.lp + cal_lp` and `new_entry.cost == old_entry.cost + intent_usd_value`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`

   - `L1DepositIntent` token is burnt
   - The intent UTxO value returned to depositor (refund)
   - Signed by the depositor (derived from `lp_address`)
   - No vault interaction required

## Fund Flow

```
User funds → L1DepositIntent → Vault → AppVault (regular deposit)
                                ↓
                        Vault's account balance increases
```

## Notes

- Processed on L1 (before HydraCommit)
- User gets LP shares in the Trust Me Bro vault
- Vault acts as a normal user doing AppDeposit to main system
