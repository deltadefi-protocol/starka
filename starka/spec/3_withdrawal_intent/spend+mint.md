# Specification - WithdrawalIntent

## Parameter

- `oracle_nft`: The policy id of `OracleNFT`

## Datum

- `address`: receiver of vault value
- `amount`: `Int` - marking the withdrawal lp tokens

## User Action

1. Process Intent

   - `WithdrawalIntent` is burnt

## User Action

1. Mint - Redeemer `RMint`

   - The net `LP Token` amount sent to `WithdrawalIntent` address is equal to the datum value of `WithdrawalIntent`

2. Burn - Redeemer `RBurn (List<Int>, ByteArray, List<ByteArray>)`

   - `WithdrawalIntent` is burnt with total batched amount
   - `LP Token` is burnt with calculation of total batched value amount and signed message, assetname = `pluggable_logic`
   - `WithdrawalIntent` input datum is correspond to withdraw output value
   - oracle input with datum
   - clean oracle output and updated datum
   - vault total value changed -= total batched datum value amount
   - output operator fee
   - `utxo_ref` in `message` is vault oracle utxo
   - verify signatures and keys
