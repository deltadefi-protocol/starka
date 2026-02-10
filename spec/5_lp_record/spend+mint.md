# Specification - LP Record

## Parameter

- `app_oracle`: PolicyId
- `vault_oracle`: PolicyId

## Datum

- `address`: receiver of vault value
- `lp`: `Int` - marking the LP quantity
- `cost`: `Int` - the cost of LP in USD value

## User Action - Spend

1. Update LP Balance

   - Either `DepositIntent` or `WithdrawalIntent` is burnt

## User Action - Mint

1. Mint - First Deposit

   - `DepositIntent` is burnt

2. Burn - Total Withdrawal

   - `WithdrawalIntent` is burnt
