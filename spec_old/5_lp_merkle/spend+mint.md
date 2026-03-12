# Specification - LP Merkle

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId

## Data Model

- **Datum**: `lp_merkle_root`: ByteArray (32-byte MPF root hash)
- **MPF Key**: `cbor.serialise(address)` where address is the user's Cardano Address
- **MPF Value**: `cbor.serialise(LPRecordEntry { lp: Int, cost: Int })`
- **Empty tree**: `null_hash` from MPF library (no depositors)

## LP MPF Action Type

```
LPMPFAction =
  | LPInsert { proof: Proof, new_value: ByteArray }
  | LPUpdate { from: ByteArray, to: ByteArray, to_proof: Proof }
  | LPDelete { proof: Proof, old_value: ByteArray }
```

## User Action - Spend

1. ProcessDeposit

   - `DepositIntent` or `L2DepositIntent` is burnt

2. ProcessWithdrawal

   - `WithdrawalIntent` or `L2WithdrawalIntent` is burnt

3. CreateVaultLP

   - `VaultState` is minted (vault creation)

4. HydraCommit

   - All hydra signers sign (move to Hydra head)

5. HydraDecommit

   - All hydra signers sign (move back to L1)

## User Action - Mint

1. Mint - `MintLPMerkle`

   - `VaultState` is minted
   - Operator signs
   - Initial empty root

2. Burn - `BurnLPMerkle`

   - `VaultState` is burnt (vault close)
   - Root must equal empty tree hash (`null_hash`)

## Security

The LP Merkle validator only guards WHEN the UTXO can be spent. The correctness of Merkle root transitions (proof verification, LP calculation) is enforced by the intent validators that trigger the spend.
