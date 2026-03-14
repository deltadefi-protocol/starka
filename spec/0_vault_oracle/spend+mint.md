# Specification - Vault Oracle

The Vault Oracle UTxO holds config and shares state. This is the only UTxO committed to Hydra.

## Parameter

- `initial_utxo`: OutputReference (one-shot UTxO consumed at CreateVault — guarantees unique policy_id)
- `app_oracle`: PolicyId (used only at CreateVault to validate `hydra_node_pub_keys`)

## Datum

### Config (updatable via UpdateConfig)

- `app_oracle`: PolicyId
- `vault_script_hash`: ByteArray (links to the Vault holding funds)
- `l1_deposit_intent_script_hash`: ByteArray
- `l1_withdrawal_intent_script_hash`: ByteArray
- `l2_deposit_intent_script_hash`: ByteArray
- `l2_withdrawal_intent_script_hash`: ByteArray
- `vault_stake_rotation_script_hash`: ByteArray
- `hydra_node_pub_keys`: List\<VerificationKey\>
- `pluggable_logic`: ByteArray
- `operator_key`: VerificationKeyHash
- `operator_charge_percentage`: Int
- `operator_min_deposit_percentage`: Int
- `is_active`: Bool - whether the vault accepts new deposits

### State (mutable)

- `total_shares`: Int - total shares outstanding
- `operator_shares`: Int - operator's shares (includes accumulated fee shares)
- `total_deposited`: Int - total cost basis of all depositors in USD
- `shares_merkle_root`: ByteArray (32-byte MPF root hash)
- `total_fee_collected`: Int - cumulative performance fees collected (in USD)

## Shares Merkle Entry

Each depositor has one entry in the shares merkle tree:

- **Key**: `cbor.serialise(address)` — the depositor's Cardano Address
- **Value**: `cbor.serialise(SharesRecordEntry { shares: Int, total_deposited: Int })`
  - `shares`: the depositor's share count
  - `total_deposited`: the depositor's total cost basis in USD (used for performance fee calculation)
- **Empty tree**: `null_hash` (no depositors)

## User Action - Mint

1. CreateVault - `CreateVault { initial_deposit, initial_shares, prices_message, signatures, initial_shares_proof }`
   - **One-shot**: `initial_utxo` (parameter) must be consumed — guarantees unique policy_id
   - `app_oracle` is referenced to obtain `hydra_signers`
   - Verify `hydra_node_pub_keys` in output datum match `app_oracle`
   - Verify `prices` message signatures
   - Initial state: `total_shares = initial_shares`, `operator_shares = initial_shares`, `total_deposited` from price calculation
   - `initial_shares` must equal `total_deposited` (genesis share price = 1.0)
   - `shares_merkle_root`: computed from inserting operator's initial shares entry
   - `initial_deposit` value goes to Vault UTxO (separate from Oracle)
   - **Signed by `operator_key` AND `operation_key` (from app_oracle)**

2. CloseVault - `CloseVault`
   - Vault Oracle NFT is burnt
   - `shares_merkle_root` must equal empty tree hash (`null_hash`)
   - `total_shares` == 0
   - **Signed by `operator_key` AND `operation_key` (from app_oracle)**

## User Action - Spend

1. ProcessL1Deposit
   - `L1DepositIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L1 deposit intent mint validator
   - Vault UTxO spent in same transaction (funds flow: User → Vault → AppVault)

2. ProcessL1Withdrawal
   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L1 withdrawal intent mint validator
   - Vault UTxO spent in same transaction (funds flow: Vault account → Vault → User)

3. ProcessL2Deposit
   - `L2DepositIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L2 deposit intent mint validator
   - Transfers balance from user's Account UTxO to vault's Account UTxO

4. ProcessL2Withdrawal
   - `L2WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L2 withdrawal intent mint validator
   - Transfers balance from vault's Account UTxO to user's Account UTxO

5. HydraCommit
   - All `hydra_node_pub_keys` sign the transaction

6. HydraDecommit
   - All `hydra_node_pub_keys` sign the transaction
   - Input and output equal

7. PluggableLogic (aribtrage vault)
   - Withdrawal Script `pluggable_logic` is validated

8. UpdateConfig
   - **Signed by all `hydra_node_pub_keys`**
   - All config fields can be modified
   - Constraints:
     - `operator_charge_percentage` must be >= 0 and <= 100
     - `hydra_node_pub_keys` must match `app_oracle` signers (if `app_oracle` changed)
   - State fields unchanged

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
- **Funds separation**: Funds stay in Vault on L1; only Oracle state enters Hydra

## Lifecycle

```
CreateVault -> L1 deposits (User → Vault → AppVault)
            -> HydraCommit (Oracle enters Hydra, Vault stays on L1)
            -> L2 deposits/withdrawals (account balance transfers)
            -> HydraDecommit (Oracle returns to L1)
            -> L1 withdrawals (Vault account → Vault → User)
            -> CloseVault (when total_shares == 0)
```
