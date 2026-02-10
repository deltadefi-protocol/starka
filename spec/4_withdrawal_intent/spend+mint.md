# Specification - WithdrawalIntent

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId
- `vault_config`: PolicyId

## Datum

- `address`: receiver of vault value
- `amount`: `Int` - marking the withdrawal lp tokens

## User Action - Spend

1. Process Intent

   - `WithdrawalIntent` is burnt

## User Action - Mint

1. Mint - Redeemer `RMint`

   - The net `LP Token` amount sent to `WithdrawalIntent` address is equal to the datum value of `WithdrawalIntent`

2. Burn - Redeemer `RBurn (List<Int>, ByteArray, List<ByteArray>)`

   - `WithdrawalIntent` is burnt with total batched amount
   - `WithdrawalIntent` input datum is correspond to withdraw output value
   - `VaultState` input with datum
   - clean `VaultState` output and updated datum
   - vault total value changed -= total batched datum value amount
   - output operator fee
   - Verify `prices` message:
      - `utxo_ref` in `message` is `VaultState` utxo
      - verify signatures and keys
   - `LP amount` is deducted from the withdrawer's `LP Record`. Either in:
     - Total withdrawal
       - Burn the `LP Record` token at `LP Record` address, with the pre-burnt amount as current withdraw LP amount
       - Only 1 input from `LP Record`
     - Update LP Value
       - Re-spend the `LP Record` UTXO and deduct the LP amount
       - No minting or burning of `LP Record`
