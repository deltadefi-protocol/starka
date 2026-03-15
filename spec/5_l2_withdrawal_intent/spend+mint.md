# Specification - L2 Withdrawal Intent

L2 withdrawal intents are created and processed inside the Hydra head. User redeems LP shares to receive balance in their Account UTxO.

## Parameter

- `vault_oracle_nft`: PolicyId

## Datum

- `withdrawer`: Address - receiver of funds
- `shares_to_redeem`: `Int` - LP shares to withdraw

## User Action - Spend

1. Process Intent
   - `L2WithdrawalIntent` is burnt

## User Action - Mint

1. MintIntent - Redeemer `MintIntent`
   - Amount > 0
   - Intent UTxO only contains the intent token (no value)

2. BurnIntent - Redeemer `BurnIntent (List<Int>, ByteArray, List<ByteArray>, List<SharesMPFAction>)`
   - **Signed by `operation_key` from `app_oracle` OR `operator_key` from vault oracle**
   - `L2WithdrawalIntent` is burnt with total batched amount
   - Vault Oracle input with datum (identified by `vault_oracle_nft`)
   - Vault Oracle output with updated datum:
     - `total_shares = total_shares - sum(shares_to_redeem) + sum(fee_shares)`
     - `operator_shares += sum(fee_shares)`
     - `total_deposited -= sum(cost_basis)`
     - `shares_merkle_root` updated
     - All other datum fields unchanged
   - Balance transferred from vault to user's Account UTxO (via TransferIntent)
   - **Each withdrawal's calculated `net_payout` must equal the corresponding TransferIntent's `amount_l2` (in USD value)**
   - Verify `prices` message using `hydra_node_pub_keys` from Oracle datum
   - Shares Merkle root transition:
     - For each withdrawal intent (chained sequentially):
       - Calculate `gross_value = shares_to_redeem * vault_equity / total_shares`
       - **Total withdrawal** (`SharesDelete`): Verify `shares_to_redeem == shares_record.shares`. `cost_basis = shares_record.total_deposited`. Delete leaf.
       - **Partial withdrawal** (`SharesUpdate`): `cost_basis = old_entry.total_deposited * shares_to_redeem / old_entry.shares`. Verify `new_entry.shares == old_entry.shares - shares_to_redeem`
       - Fee calculation: `fee = max(0, (gross_value - cost_basis) * operator_charge_percentage / 100)` (round UP)
       - Fee shares: `fee_shares = fee * total_shares / vault_equity` (round UP)
       - Net payout: `net_payout = gross_value - fee` (round DOWN)
     - After all withdrawals, apply operator fee share action if `total_fee_shares > 0`
     - Verify `computed_final_root == expected_final_root`

3. CancelIntent - Redeemer `CancelIntent`
   - `L2WithdrawalIntent` token is burnt
   - **Signed by `operation_key` from `app_oracle`**
   - Vault Oracle input required (to get `app_oracle` reference)
   - No value refund needed (intent only contains intent token)

## Balance Flow

```
Vault's Account UTxO → (TransferIntent) → User's Account UTxO
```

## Validation Rules (ref: vault-spec 4.6)

1. `shares_to_redeem > 0` AND `shares_to_redeem <= user_shares_balance` (from merkle proof)
2. `share_price` computed from current `vault_equity / total_shares`
3. `gross_profit = max(0, gross_value - cost_basis)` (never negative)
4. `fee = gross_profit * operator_charge_percentage / 100` (round UP)
5. `fee_shares` correctly computed and added to operator merkle record
6. `net_payout = gross_value - fee` transferred to user's Account (via TransferIntent)
7. **Each `net_payout` must equal the corresponding `amount_l2` in TransferIntent (in USD value)** (prevents incorrect payout amounts)
8. Sufficient balance in vault's Account to cover net_payout
9. `new_total_shares = old_total_shares - shares_redeemed + fee_shares`
10. `new_total_deposited = old_total_deposited - cost_basis_removed`

> **Asset Flexibility**: Script transfers ANY asset based on vault Account holdings. Backend determines payout asset composition. Scripts should never change; backend rules can evolve.

## Notes

- Deployed inside the Hydra head
- Intent UTxO only holds the intent token (tokens are stored in Account UTxOs)
- Vault Oracle is the only Starka UTxO in Hydra (funds stay in Vault on L1)
- Balance transfer uses HydraAccount TransferIntent mechanism
- Performance fee calculated on profit (gross_value - cost_basis)
- Vault is treated as a normal user with its own Account UTxO
- User can later do regular withdrawal to get actual funds on L1
