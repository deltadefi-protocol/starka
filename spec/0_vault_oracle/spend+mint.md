# Specification - Vault Oracle

The Vault Oracle UTxO holds config and shares state. This is the only UTxO committed to Hydra.

## Parameter

- `initial_utxo`: OutputReference (one-shot UTxO consumed at MintOracle — guarantees unique policy_id)

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
- `operator_account`: UserAccount (contains Account with master_key, operation_key, account_id)
- `operator_charge_percentage`: Int
- `operator_min_deposit_percentage`: Int
- `is_active`: Bool - whether the vault accepts new deposits

### State (mutable)

- `total_shares`: Int - total shares outstanding
- `operator_shares`: Int - operator's shares (includes accumulated fee shares)
- `total_deposited`: Int - total cost basis of all depositors in USD
- `shares_merkle_root`: ByteArray (32-byte MPF root hash)
- `total_fee_share_collected`: Int - cumulative fee shares collected

## Shares Merkle Entry

Each depositor has one entry in the shares merkle tree:

- **Key**: `cbor.serialise(account)` — the depositor's Account (account_id, master_key, operation_key)
- **Value**: `cbor.serialise(SharesRecordEntry { shares: Int, total_deposited: Int })`
  - `shares`: the depositor's share count
  - `total_deposited`: the depositor's total cost basis in USD (used for performance fee calculation)
- **Empty tree**: `null_hash` (no depositors)

## User Action - Mint

The mint policy is a simple one-time minting policy (similar to `app_oracle/oracle_nft.ak`).

1. MintOracle - `RMint`
   - **One-shot**: `initial_utxo` (parameter) must be consumed — guarantees unique policy_id
   - Exactly 1 NFT minted
   - Output datum contains initial config (all state fields = 0, `shares_merkle_root = null_hash`)
   - No signatures required (anyone can create a vault)

2. CloseVault - `CloseVault`
   - Vault Oracle NFT is burnt
   - `shares_merkle_root` must equal empty tree hash (`null_hash`)
   - `total_shares == 0`
   - **Signed by `operator_account.account.master_key` AND `operation_key` (from app_oracle)**

## User Action - Spend

1. L1InitialDeposit - `L1InitialDeposit { depositor, initial_deposit, prices_message, signatures, initial_shares_proof }`
   - **Precondition**: `total_shares == 0` (vault is empty/new)
   - `app_oracle` is referenced to obtain `hydra_signers`
   - Verify `hydra_node_pub_keys` in output datum match `app_oracle`
   - Verify `prices` message signatures using `hydra_signers`
   - Calculate `initial_shares` from `initial_deposit` USD value (share price = 1.0)
   - Initial state: `total_shares = initial_shares`, `operator_shares = 0`, `total_deposited = initial_shares`
   - `shares_merkle_root`: computed from inserting depositor's initial shares entry (key = `cbor.serialise(depositor)`)
   - `initial_deposit` value goes to Vault UTxO (separate from Oracle)
   - **Anyone can perform initial deposit (no signature required)**

2. ProcessL1Deposit
   - `L1DepositIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L1 deposit intent mint validator
   - Vault UTxO spent in same transaction (funds flow: User → Vault → AppVault)

3. ProcessL1Withdrawal
   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L1 withdrawal intent mint validator
   - Vault UTxO spent in same transaction (funds flow: Vault account → Vault → User)

4. ProcessL2Deposit
   - `L2DepositIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L2 deposit intent mint validator
   - Transfers balance from user's Account UTxO to vault's Account UTxO

5. ProcessL2Withdrawal
   - `L2WithdrawalIntent` token is burnt with `BurnIntent` redeemer
   - All validation delegated to L2 withdrawal intent mint validator
   - Transfers balance from vault's Account UTxO to user's Account UTxO

6. HydraCommit
   - All `hydra_node_pub_keys` sign the transaction

7. HydraDecommit
   - All `hydra_node_pub_keys` sign the transaction
   - Input and output equal

8. PluggableLogic (arbitrage vault)
   - Withdrawal Script `pluggable_logic` is validated

9. UpdateConfig

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

**Path A: L1 Initial Deposit**

```
MintOracle -> L1InitialDeposit -> L1 deposits -> HydraCommit -> L2 ops -> HydraDecommit -> L1 withdrawals -> CloseVault
```

**Path B: L2 Initial Deposit**

```
MintOracle -> HydraCommit -> L2InitialDeposit -> L2 ops -> HydraDecommit -> L1 withdrawals -> CloseVault
```
