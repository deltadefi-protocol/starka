# Specification - Vault Oracle

Split oracle design: two NFTs under the same policy, distinguished by datum type.

| Oracle | Datum Type | Location | Purpose |
|--------|------------|----------|---------|
| **Config Oracle** | `VaultConfig` | Always L1 | Config for L1 operations |
| **State Oracle** | `VaultOracleDatum` | L1 or L2 (Hydra) | Config copy + state |

Both oracles share the same `policy_id` and token name `""`. Config may diverge between the two - this is acceptable.

## Parameter

- `initial_utxo`: OutputReference (one-shot UTxO consumed at MintOracle — guarantees unique policy_id)
- `app_oracle`: PolicyId

## Datum - Config Oracle (L1 only)

Simplified config with only shared fields needed for L1 operations.

```
VaultConfig {
  app_oracle: PolicyId,
  l1_deposit_intent_script_hash: ByteArray,
  l1_withdrawal_intent_script_hash: ByteArray,
  l2_deposit_intent_script_hash: ByteArray,
  l2_withdrawal_intent_script_hash: ByteArray,
  pluggable_logic: ByteArray,
  operator_account: UserAccount,
  hydra_node_pub_keys: List<VerificationKey>,
}
```

## Datum - State Oracle (L1 or L2)

```
VaultOracleDatum {
  // Config (copy, may diverge from Config Oracle)
  app_oracle: PolicyId,
  vault_script_hash: ByteArray,
  l1_deposit_intent_script_hash: ByteArray,
  l1_withdrawal_intent_script_hash: ByteArray,
  l2_deposit_intent_script_hash: ByteArray,
  l2_withdrawal_intent_script_hash: ByteArray,
  pluggable_logic: ByteArray,
  vault_stake_rotation_script_hash: ByteArray,
  operator_account: UserAccount,
  operator_charge_percentage: Int,
  operator_min_deposit_percentage: Int,
  hydra_node_pub_keys: List<VerificationKey>,
  is_active: Bool,

  // State (mutable)
  total_shares: Int,
  operator_shares: Int,
  total_deposited: Int,
  shares_merkle_root: ByteArray,
  total_fee_share_collected: Int,
}
```

## Shares Merkle Entry

Each depositor has one entry in the shares merkle tree:

- **Key**: `cbor.serialise(account)` — the depositor's Account (account_id, master_key, operation_key)
- **Value**: `cbor.serialise(SharesRecordEntry { shares: Int, total_deposited: Int })`
  - `shares`: the depositor's share count
  - `total_deposited`: the depositor's total cost basis in USD (used for performance fee calculation)
- **Empty tree**: `null_hash` (no depositors)

## User Action - Mint

### MintVault - `MintVault`

- **One-shot**: `initial_utxo` (parameter) must be consumed — guarantees unique policy_id
- **Exactly 2 NFTs minted** (same token name `""`, distinguished by datum type)
- `app_oracle` is referenced to verify `hydra_node_pub_keys`
- Two outputs at script address:
  - **Config Oracle**: `VaultConfig` datum
  - **State Oracle**: `VaultOracleDatum` datum
- Shared config fields must match between both datums:
  - `app_oracle`, `l1_deposit_intent_script_hash`, `l1_withdrawal_intent_script_hash`
  - `l2_deposit_intent_script_hash`, `l2_withdrawal_intent_script_hash`
  - `pluggable_logic`, `operator_account`, `hydra_node_pub_keys`
- State Oracle: all state fields = 0, `shares_merkle_root = null_hash`
- `operator_charge_percentage` must be >= 0 and <= 100
- No signatures required (anyone can create a vault)

### CloseVault - `CloseVault`

- **Both NFTs burnt** (Config Oracle + State Oracle = -2)
- Two inputs at script address:
  - **Config Oracle**: `VaultConfig` datum
  - **State Oracle**: `VaultOracleDatum` datum
- State Oracle: `shares_merkle_root` must equal empty tree hash, `total_shares == 0`
- **Signed by `operator_account.account.master_key` AND `operation_key` (from app_oracle)**

## User Action - Spend

The spend handler accepts both `VaultConfig` and `VaultOracleDatum` as datum, distinguished by type.

> **Note**: Initial deposits (both L1 and L2) are handled by the respective intent validators when `total_shares == 0`. This follows the pattern in `hydra_account/vault_deposit.ak` where initial deposit is treated as a regular deposit with share price = 1.0.

### State Oracle Actions (VaultOracleDatum)

1. **ProcessL1Deposit**
   - `L1DepositIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L1 deposit intent mint validator
   - Vault UTxO spent in same transaction (funds flow: User → Vault → AppVault)

2. **ProcessL1Withdrawal**
   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L1 withdrawal intent mint validator
   - Vault UTxO spent in same transaction (funds flow: Vault account → Vault → User)

3. **ProcessL2Deposit**
   - `L2DepositIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L2 deposit intent mint validator
   - Transfers balance from user's Account UTxO to vault's Account UTxO

4. **ProcessL2Withdrawal**
   - `L2WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L2 withdrawal intent mint validator
   - Transfers balance from vault's Account UTxO to user's Account UTxO

5. **HydraCommit**
   - All `hydra_node_pub_keys` sign the transaction

6. **HydraDecommit**
   - All `hydra_node_pub_keys` sign the transaction
   - Input and output equal

7. **PluggableLogic** (L2 trading)
   - Withdrawal Script `pluggable_logic` is validated

8. **UpdateConfig** (State Oracle)
   - **Signed by all `hydra_node_pub_keys`**
   - All config fields can be modified
   - State fields can be modified (no restriction when spending State Oracle)
   - Constraints:
     - `operator_charge_percentage` must be >= 0 and <= 100

9. **BurnVault**
   - Oracle NFT is being burnt (minted_quantity < 0)
   - Allows spending oracle as part of CloseVault mint action

### Config Oracle Actions (VaultConfig)

The Config Oracle stays on L1 and supports these actions:

1. **UpdateConfig** (Config Oracle)
   - **Signed by all `hydra_node_pub_keys`**
   - All config fields can be modified
   - **State fields in output must remain unchanged** (0 values)
   - Constraints:
     - `operator_charge_percentage` must be >= 0 and <= 100

2. **PluggableLogic** (L1 pluggable logic)
   - Withdrawal Script `pluggable_logic` is validated
   - Allows L1 pluggable logic execution while State Oracle is in Hydra

3. **BurnVault**
   - Oracle NFT is being burnt (minted_quantity < 0)
   - Allows spending oracle as part of CloseVault mint action

## Script Upgrades

To upgrade any script (vault, intents, etc.):

1. Deploy new script
2. Migrate any funds/state if needed
3. Call `UpdateConfig` to update the script hash
4. Future operations use new script

## Security

- **One-shot uniqueness**: `initial_utxo` makes each vault's policy_id unique
- **Guard pattern**: Checks intent tokens burned with `BurnIntent` (not `CancelIntent`)
- **Hydra signatures**: Commit/Decommit require all hydra node signatures
- **Funds separation**: Funds stay in Vault on L1; only State Oracle enters Hydra
- **Config availability**: Config Oracle always on L1 for L1 operations

## Config Divergence

The two oracles' config may diverge:

| Scenario | Config Oracle (L1) | State Oracle (L2) | Impact |
|----------|-------------------|-------------------|--------|
| Update pluggable_logic on L1 | Updated | Old | L1 uses new logic, L2 uses old |
| Update pluggable_logic on L2 | Old | Updated | L1 uses old logic, L2 uses new |
| Update both | Updated | Updated | Both in sync |

**Design Choice**: Divergence is acceptable because:
1. L1 and L2 operations are independent
2. Operator can sync manually via UpdateConfig on both if needed
3. Simplifies implementation (no cross-layer sync required)

## Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                         MINT PHASE                              │
│          MintVault (mints config + state NFTs)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                 ▼
    ┌─────────────────┐               ┌─────────────────┐
    │  Path A: L1     │               │  Path B: L2     │
    │ Initial Deposit │               │ Initial Deposit │
    └────────┬────────┘               └────────┬────────┘
             │                                 │
             │ (State Oracle on L1)            │ HydraCommit
             │                                 │ (State Oracle only)
             ▼                                 ▼
    ┌─────────────────┐               ┌─────────────────┐
    │ L1InitialDeposit│               │ L2InitialDeposit│
    │ (state spent)   │               │ (in Hydra)      │
    └────────┬────────┘               └────────┬────────┘
             │                                 │
             │ HydraCommit (State Oracle)      │
             └────────────────┬────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ACTIVE TRADING PHASE                       │
│              Config Oracle: L1    State Oracle: Hydra           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  L2 Operations (State Oracle in Hydra):                         │
│    ✓ ProcessL2Deposit                                           │
│    ✓ ProcessL2Withdrawal                                        │
│    ✓ PluggableLogic (L2 trading)                                │
│    ✓ UpdateConfig (L2)                                          │
│                                                                 │
│  L1 Operations (Config Oracle on L1):                           │
│    ✓ VaultPluggableLogic (ref config oracle)                    │
│    ✓ StakeRotation (ref config oracle)                          │
│    ✓ DepositIntoDeltaDeFi (ref config oracle)                   │
│    ✓ UpdateConfig (L1 config oracle)                            │
│    ✗ ProcessWithdrawal (needs state oracle on L1)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HydraDecommit (State Oracle)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      L1 SETTLEMENT PHASE                        │
│              Config Oracle: L1    State Oracle: L1              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ✓ ProcessL1Withdrawal (state oracle spent + vault spent)     │
│    ✓ ProcessL1Deposit                                           │
│    ✓ All L1 operations                                          │
│                                                                 │
│    Can re-commit: HydraCommit → back to Active Trading Phase    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ (when total_shares == 0)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLOSE VAULT                             │
│               Burn both Config + State Oracles                  │
└─────────────────────────────────────────────────────────────────┘
```

> Initial deposits use the same flow as regular deposits. When `total_shares == 0`, the share price is 1.0 (shares = USD value).
