# Specification - WithdrawalIntent

## Parameter

- `oracle_nft`: The policy id of `OracleNFT`

## User Action

1. Mint - Redeemer `RMint`

   - The net `LP Token` amount sent to `WithdrawalIntent` address is equal to the datum value of `WithdrawalIntent`

2. Burn - Redeemer `RBurn (Pairs<Int,Int>, ByteArray, ByteArray)`

   - `DepositIntent` is burnt with total batched amount
   - `LP Token` is burnt with calculation of total batched value amount and signed message, assetname = `pluggable_logic`
   - `WithdrawalIntent` input datum is correspond to withdraw output value
   - oracle input with datum
   - clean oracle output and updated datum
   - vault total value changed -= total batched datum value amount
