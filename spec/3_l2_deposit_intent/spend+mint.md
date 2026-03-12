# Specification - L2 Deposit Intent

L2 deposit intents are created and processed inside the Hydra head. User transfers balance from their Account UTxO to the vault to receive LP shares.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `lp_address`: Address - receiver of LP
- `amount`: `MValue` - in hydra token representation

## User Action - Spend

1. Process Intent

   - `L2DepositIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`

   - Deposit amount > 0
   - Intent UTxO only contains the intent token (no deposit value)
   - Tokens are stored in user's Account UTxO

2. BurnIntent - Redeemer `BurnIntent (List<Int>, List<Int>, ByteArray, List<ByteArray>, List<LPMPFAction>)`

   - `L2DepositIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_lp += sum(cal_lp)` across all intents
     - `vault_cost += sum(intent_usd_value)` across all intents
     - `lp_merkle_root` updated (see LP Merkle transition below)
     - All other datum fields unchanged
   - Balance transferred from user's Account UTxO to vault (via TransferIntent)
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - LP Merkle root transition:
     - For each deposit intent (chained sequentially):
       - Calculate `cal_lp = intent_usd_value * total_lp / vault_balance` (round DOWN)
       - **New depositor** (`LPInsert`): Insert `LPRecordEntry { lp: cal_lp, cost: intent_usd_value }`
       - **Existing depositor** (`LPUpdate`): Verify `new_entry.lp == old_entry.lp + cal_lp` and `new_entry.cost == old_entry.cost + intent_usd_value`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`

   - `L2DepositIntent` token is burnt
   - Signed by the depositor (derived from `lp_address`)
   - No value refund needed (tokens are in Account UTxO, not intent)
   - No vault interaction required

## Balance Flow

```
User's Account UTxO → (TransferIntent) → Vault's Account UTxO
```

## Notes

- Deployed inside the Hydra head
- Intent UTxO only holds the intent token (tokens are stored in Account UTxOs)
- Vault Oracle is the only Starka UTxO in Hydra (LP funds stay in Vault on L1)
- User must have sufficient balance in their Account UTxO (from prior regular deposit)
- Balance transfer uses HydraAccount TransferIntent mechanism
- Vault is treated as a normal user with its own Account UTxO
