# Specification - DepositIntent

## Parameter

- `oracle_nft`: The policy id of `OracleNFT`

## Datum

- `address`: receiver of `LP Token`
- `amount`: `MValue` - marking the deposit balance

## User Action

1. Process Intent

   - `DepositIntent` is burnt

## User Action

1. Mint - Redeemer `RMint`

   - The net deposit value sent to `DepositIntent` address is equal to the datum value of `DepositIntent`

2. Burn - Redeemer `RBurn (List<Int>, ByteArray, List<ByteArray>)`

   - only one `app_deposit_token` is minted and output datum equal to total batched datum value amount
   - `DepositIntent` is burnt with total batched amount
   - `LP Token` is minted with calculation of total batched value amount and signed message, assetname = `pluggable_logic`
   - `DepositIntent` input datum is correspond to `LP Token` output amount
   - oracle input with datum
   - clean oracle output and updated datum
   - `utxo_ref` in `message` is vault oracle utxo
   - verify signatures and keys
