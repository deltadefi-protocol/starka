# Starka Vault

Cardano Plutus V3 vault smart contracts. Import path: `deltadefi-protocol/starka`

## Package Info

| Property | Value |
|----------|-------|
| Import Path | `deltadefi-protocol/starka` |
| Language | Aiken |
| Type | schema (on-chain validators, consumed as compiled `plutus.json`) |

## Validators

| Validator | Parameters | Purposes | Description |
|-----------|------------|----------|-------------|
| `vault` | `initial_utxo`, `app_oracle` | spend, mint | Core vault: create/close vault, process intents, hydra commit/decommit, trade |
| `l1_deposit_intent` | `vault_nft` | spend, mint | L1 deposit intent: mint/burn/cancel deposit intents with batched MPF updates |
| `l1_withdrawal_intent` | `vault_nft` | spend, mint | L1 withdrawal intent: mint/burn/cancel withdrawal intents with fee calculation |
| `l2_deposit_intent` | `vault_nft` | spend, mint | L2 deposit intent: same as L1 deposit for Layer 2 |
| `l2_withdrawal_intent` | `vault_nft` | spend, mint | L2 withdrawal intent: same as L1 withdrawal for Layer 2 |

## Exported Types

| Type | File | Description |
|------|------|-------------|
| `MValue` | `lib/types.ak` | Multi-asset value as `Pairs<PolicyId, Pairs<AssetName, Int>>` |
| `MintPolarity` | `lib/types.ak` | Mint/Burn enum for oracle NFT operations |
| `VaultDatum` | `lib/types.ak` | Vault UTxO datum: config (oracle, scripts, operator) + state (lp, cost, merkle root) |
| `VaultMintRedeemer` | `lib/types.ak` | CreateVault (with initial deposit + MPF proof) or CloseVault |
| `VaultSpendRedeemer` | `lib/types.ak` | ProcessL1/L2 Deposit/Withdrawal, HydraCommit/Decommit, Trade, PluggableLogic |
| `IntentRedeemer` | `lib/types.ak` | MintIntent, BurnIntent (batched with MPF actions), CancelIntent |
| `LPMPFAction` | `lib/types.ak` | MPF trie operations: LPInsert, LPUpdate, LPDelete with proofs |
| `LPRecordEntry` | `lib/types.ak` | LP position record: `{lp, cost}` stored serialized in MPF trie |
| `Message` | `lib/types.ak` | Oracle price message: vault_balance, prices, utxo_ref |
| `DepositIntentDatum` | `lib/types.ak` | Deposit intent: lp_address + amount (MValue) |
| `WithdrawalIntentDatum` | `lib/types.ak` | Withdrawal intent: lp_address + amount (LP Int) |

## Compiled Output

| File | Format | Consumer |
|------|--------|----------|
| `plutus.json` | CIP-0057 blueprint | Off-chain operator service builds transactions from compiled validators |

---

Internal structure: See `CLAUDE.md`
