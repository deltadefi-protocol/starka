# Specification - DepositIntent

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId
- `vault_config`: PolicyId

## Datum

- `address`: receiver of `LP Token`
- `amount`: `MValue` - marking the deposit balance

## User Action - Spend

1. Process Intent

   - `DepositIntent` is burnt

## User Action - Mint

1. Mint - Redeemer `RMint`

   - The net deposit value sent to `DepositIntent` address is equal to the datum value of `DepositIntent`

2. Burn - Redeemer `RBurn (List<Int>, ByteArray, List<ByteArray>)`

   - `DepositIntent` is burnt with total batched amount
   - `VaultState` input with datum
   - Clean `VaultState` output and updated datum
   - The deposit value is sent to the address with `vault_script_hash`
   - Verify `prices` message:
      - `utxo_ref` in `message` is `VaultState` utxo
      - verify signatures and keys
   - `LP amount` is added to the depositor `LP Record`. Either in:
     - New depositor
       - Mint a new `LP Record` token at `LP Record` address, with the initial amount as current deposit LP amount
       - There is no input from `LP Record`
     - Update LP Value
       - Re-spend the `LP Record` UTXO and add the LP amount
       - no minting of `LP Record`
