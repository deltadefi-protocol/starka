# Specification - Vault

The single Vault UTxO merges oracle config, vault state, vault funds, and LP merkle root. This is the only UTxO committed to Hydra.

## Parameter

- `initial_utxo`: OutputReference (one-shot UTxO consumed at CreateVault — guarantees unique policy_id per vault)
- `app_oracle`: PolicyId (used only at CreateVault to validate `hydra_node_pub_keys`; not needed during lifecycle operations)

## Datum

### Config (immutable after creation)

- `app_oracle`: PolicyId (used at CreateVault to cross-check `hydra_node_pub_keys`; not referenced during lifecycle)
- `l1_deposit_intent_script_hash`: ByteArray
- `l1_withdrawal_intent_script_hash`: ByteArray
- `l2_deposit_intent_script_hash`: ByteArray
- `l2_withdrawal_intent_script_hash`: ByteArray
- `pluggable_logic`: ByteArray
- `vault_stake_rotation_script_hash`: ByteArray
- `operator_key`: VerificationKeyHash
- `operator_charge_percentage`: Int
- `operator_min_deposit_percentage`: Int
- `hydra_node_pub_keys`: List\<VerificationKey\>

### State (mutable)

- `total_lp`: Int - total LP shares outstanding
- `operator_lp`: Int - operator's LP shares (includes accumulated fee shares)
- `vault_cost`: Int - total cost basis of all depositors in USD
- `lp_merkle_root`: ByteArray (32-byte MPF root hash)

## LP Merkle Entry

Each depositor has one entry in the LP merkle tree:

- **Key**: `cbor.serialise(address)` — the depositor's Cardano Address
- **Value**: `cbor.serialise(LPRecordEntry { lp: Int, cost: Int })`
  - `lp`: the depositor's LP share count
  - `cost`: the depositor's total cost basis in USD (used for performance fee calculation)
- **Empty tree**: `null_hash` (no depositors)

## User Action - Mint

1. CreateVault - `CreateVault { initial_deposit, initial_lp, prices_message, signatures, initial_lp_proof }`

   - **One-shot**: `initial_utxo` (parameter) must be consumed in the transaction — guarantees this mint can only happen once, producing a unique policy_id
   - Current `policy_id` token with empty string is minted to own script address, obtain the datum
   - `app_oracle` is referenced (reference input) to obtain `hydra_signers` (list of `VerificationKeyHash`)
   - Verify `hydra_node_pub_keys` in output datum match `app_oracle`:
     - For each pair: `blake2b_224(hydra_node_pub_key) == hydra_signer`
     - This is the **only time** `app_oracle` is used — once validated at creation, all subsequent operations verify prices directly against the immutable `hydra_node_pub_keys` in the vault datum
   - Verify `prices` message:
     - `utxo_ref` included in inputs
     - verify ed25519 signatures against `hydra_node_pub_keys` from output datum
   - Check against the datum:
     - `app_oracle`: matches validator parameter `app_oracle`
     - `total_lp`: Same as `initial_lp`
     - `operator_lp`: Same as `initial_lp`
     - `vault_cost`: Obtained by price calculation
     - `initial_lp` must equal `vault_cost` (genesis share price = 1.0)
     - `lp_merkle_root`: computed from inserting operator's initial LP entry into empty tree
   - `initial_deposit` value is held in the Vault UTxO itself (funds are co-located with state)
   - Redeemer includes `initial_lp_proof: Proof` (MPF insert proof for operator entry)
   - The inserted entry: key = `cbor.serialise(operator_address)`, value = `cbor.serialise(LPRecordEntry { lp: initial_lp, cost: vault_cost })`
   - `operator_charge_percentage` >= 0 and <= 100
   - Non zero initial LPs
   - Sign by operator (obtained from datum)

2. CloseVault - `CloseVault`

   - Vault NFT is burnt
   - `lp_merkle_root` must equal empty tree hash (`null_hash`)
   - `total_lp` == 0
   - Signed by operator

## User Action - Spend

1. ProcessL1Deposit

   - `L1DepositIntent` token is burnt with `BurnIntent` redeemer (verify redeemer in tx redeemers map — must not be `CancelIntent`)
   - All validation delegated to L1 deposit intent mint validator (datum transition, value changes, price verification, merkle proofs)

2. ProcessL1Withdrawal

   - `L1WithdrawalIntent` token is burnt with `BurnIntent` redeemer (verify redeemer in tx redeemers map)
   - All validation delegated to L1 withdrawal intent mint validator

3. ProcessL2Deposit

   - `L2DepositIntent` token is burnt with `BurnIntent` redeemer (verify redeemer in tx redeemers map)
   - All validation delegated to L2 deposit intent mint validator

4. ProcessL2Withdrawal

   - `L2WithdrawalIntent` token is burnt with `BurnIntent` redeemer (verify redeemer in tx redeemers map)
   - All validation delegated to L2 withdrawal intent mint validator

5. HydraCommit

   - All `hydra_node_pub_keys` sign the transaction
   - Datum unchanged
   - Value unchanged

6. HydraDecommit

   - All `hydra_node_pub_keys` sign the transaction
   - Datum unchanged
   - Value unchanged

8. PluggableLogic

   - Withdrawal Script `pluggable_logic` is validated

## Withdrawal

1. Hydra withdrawal - operator key signed / dd sign + process hydra withdrawal

2. Deposit into other vault - operator key signed + process hydra transferal

## Security

- **One-shot uniqueness**: The `initial_utxo` parameter makes each vault deployment's script hash (and thus policy_id and script address) unique. Since a UTxO can only be consumed once, the vault NFT can only be minted once per deployment. Intent validators parameterized with `vault_nft: PolicyId` can unambiguously identify their vault.
- The Vault spend validator uses a **guard pattern**: for ProcessL1Deposit/ProcessL1Withdrawal/ProcessL2Deposit/ProcessL2Withdrawal, it checks that the corresponding intent tokens are burned **with `BurnIntent` redeemer** (not `CancelIntent`). This prevents an attacker from spending the Vault UTxO while cancelling an intent, which would bypass all datum/value validation. All calculation correctness (LP computation, price verification, merkle proof verification) is enforced by the intent mint validators.
- HydraCommit/Decommit require all hydra node signatures, preventing unilateral fund movement.
- Trade only changes value composition, never datum state — prevents operator from manipulating LP accounting.
- **`hydra_node_pub_keys` validation**: At `CreateVault`, the `app_oracle` reference input's `hydra_signers` are cross-checked against the datum's `hydra_node_pub_keys` via `blake2b_224`. Since config fields are immutable after creation, all subsequent L1 and L2 operations verify price signatures directly against `hydra_node_pub_keys` in the vault datum — no `app_oracle` reference input needed. This simplifies L1 to use the same price verification path as L2.

## Lifecycle

```
CreateVault -> L1 deposits (ProcessL1Deposit)
            -> HydraCommit (move to Hydra)
            -> L2 deposits/withdrawals + Trade (inside Hydra)
            -> HydraDecommit (move back to L1)
            -> L1 withdrawals (ProcessL1Withdrawal)
            -> CloseVault (when total_lp == 0)
```

Shutdown: Before CloseVault, any unprocessed intents must be cancelled via `CancelIntent` on each intent validator (refunds user without vault interaction).
