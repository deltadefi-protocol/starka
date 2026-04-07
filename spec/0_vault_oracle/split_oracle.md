# Specification - Split Vault Oracle

This spec introduces a split oracle design to enable L1 operations while the state oracle is committed to Hydra L2.

## Overview

Two NFTs minted under the same policy:

| Oracle | Token Name | Location | Purpose |
|--------|------------|----------|---------|
| **Config Oracle** | `"config"` | Always L1 | Config for L1 operations |
| **State Oracle** | `"state"` | L1 or L2 (Hydra) | Full oracle with config + state |

Both oracles share the same `policy_id` (one-shot mint). Config may diverge between the two - this is acceptable.

## Parameter

- `initial_utxo`: OutputReference (one-shot UTxO consumed at MintOracle - guarantees unique policy_id)
- `app_oracle`: PolicyId

## Datum - Config Oracle (L1 only)

```
VaultConfigDatum {
  // Config
  app_oracle: PolicyId,
  vault_script_hash: ByteArray,
  l1_deposit_intent_script_hash: ByteArray,
  l1_withdrawal_intent_script_hash: ByteArray,
  l2_deposit_intent_script_hash: ByteArray,
  l2_withdrawal_intent_script_hash: ByteArray,
  vault_stake_rotation_script_hash: ByteArray,
  hydra_node_pub_keys: List<VerificationKey>,
  pluggable_logic: ByteArray,
  operator_account: UserAccount,
  operator_charge_percentage: Int,
  operator_min_deposit_percentage: Int,
  is_active: Bool,
}
```

## Datum - State Oracle (L1 or L2)

```
VaultStateDatum {
  // Config (copy, may diverge from Config Oracle)
  app_oracle: PolicyId,
  vault_script_hash: ByteArray,
  l1_deposit_intent_script_hash: ByteArray,
  l1_withdrawal_intent_script_hash: ByteArray,
  l2_deposit_intent_script_hash: ByteArray,
  l2_withdrawal_intent_script_hash: ByteArray,
  vault_stake_rotation_script_hash: ByteArray,
  hydra_node_pub_keys: List<VerificationKey>,
  pluggable_logic: ByteArray,
  operator_account: UserAccount,
  operator_charge_percentage: Int,
  operator_min_deposit_percentage: Int,
  is_active: Bool,

  // State (mutable)
  total_shares: Int,
  operator_shares: Int,
  total_deposited: Int,
  shares_merkle_root: ByteArray,
  total_fee_share_collected: Int,
}
```

## User Action - Mint

### MintOracle - `MintOracle`

- **One-shot**: `initial_utxo` must be consumed
- **Exactly 2 NFTs minted**:
  - 1x token name `"config"` (Config Oracle)
  - 1x token name `"state"` (State Oracle)
- `app_oracle` is referenced to verify `hydra_node_pub_keys`
- Both output datums must have matching initial config
- State Oracle: all state fields = 0, `shares_merkle_root = null_hash`
- No signatures required (anyone can create a vault)

### CloseVault - `CloseVault`

- **Both NFTs burned** (config + state)
- State Oracle: `shares_merkle_root == null_hash` and `total_shares == 0`
- **Signed by `operator_account.master_key` AND `operation_key` (from app_oracle)**

## User Action - Spend (Config Oracle)

The Config Oracle stays on L1 and supports these actions:

### 1. UpdateConfig - `UpdateConfig`

- **Signed by all `hydra_node_pub_keys`**
- All config fields can be modified
- Constraints:
  - `operator_charge_percentage` must be >= 0 and <= 100
  - `hydra_node_pub_keys` must match `app_oracle` signers (if `app_oracle` changed)

### 2. PluggableLogicL1 - `PluggableLogicL1`

- Withdrawal Script `pluggable_logic` is validated
- Allows L1 pluggable logic execution while State Oracle is in Hydra

## User Action - Spend (State Oracle)

The State Oracle can be on L1 or committed to Hydra L2.

### When on L1:

1. **L1InitialDeposit** - Same as current spec
2. **ProcessL1Deposit** - `L1DepositIntent` token burnt with `BurnIntent`
3. **ProcessL1Withdrawal** - `L1WithdrawalIntent` token burnt with `BurnIntent`
4. **HydraCommit** - All `hydra_node_pub_keys` sign
5. **UpdateConfig** - All `hydra_node_pub_keys` sign, state unchanged

### When in Hydra (L2):

6. **ProcessL2Deposit** - `L2DepositIntent` token burnt with `BurnIntent`
7. **ProcessL2Withdrawal** - `L2WithdrawalIntent` token burnt with `BurnIntent`
8. **HydraDecommit** - All `hydra_node_pub_keys` sign, input == output
9. **PluggableLogic** - Withdrawal Script `pluggable_logic` validated (L2 trading)
10. **UpdateConfig** - All `hydra_node_pub_keys` sign, state unchanged

## Vault Script Changes

```
Vault Parameter:
  - vault_oracle: PolicyId  // same policy for both config and state

L1 Operations:
  ProcessWithdrawal:
    - State Oracle spent as INPUT (must be on L1)
    - L1WithdrawalIntent token burnt

  VaultPluggableLogic:
    - Config Oracle in REFERENCE_INPUTS (always available on L1)
    - Withdrawal Script pluggable_logic validated

  StakeRotation:
    - Config Oracle in REFERENCE_INPUTS
    - Withdrawal Script vault_stake_rotation_script_hash validated

  DepositIntoDeltaDeFi:
    - Config Oracle in REFERENCE_INPUTS
    - app_deposit_request_token minted
```

## Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                         MINT PHASE                              │
│            MintOracle (mints config + state NFTs)               │
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

## Security

- **One-shot uniqueness**: `initial_utxo` makes policy_id unique for both oracles
- **Guard pattern**: Intent tokens burned with `BurnIntent` (not `CancelIntent`)
- **Hydra signatures**: Commit/Decommit require all hydra node signatures
- **Funds separation**: Funds stay in Vault on L1; only State Oracle enters Hydra
- **Config availability**: Config Oracle always on L1 for L1 operations

## Migration from Single Oracle

1. Deploy new split oracle validator
2. Create new vault with split oracle (mint both NFTs)
3. Migrate funds from old vault to new vault
4. Close old vault
