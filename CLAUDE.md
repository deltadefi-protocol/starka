# Starka Vault

Cardano Plutus V3 smart contracts for DeltaDeFi's vault system, written in Aiken v1.1.17.

## Organization

| Property | Value |
|----------|-------|
| Org | `deltadefi` |
| Team | `main` |
| Config | `~/.claude/configs/orgs/deltadefi/` |

## Commands

| Task | Command |
|------|---------|
| Build | `aiken build` |
| Test | `aiken check` |
| Test (filtered) | `aiken check -m <pattern>` |

## Conventions

| Convention | Description |
|------------|-------------|
| Validator pattern | `validator name(params) { spend(...) { } mint(...) { } else(_) { fail } }` |
| Type location | All shared types centralized in `lib/types.ak` |
| Helper imports | Use `cocktail`/`vodka` helpers from `sidan-lab/vodka` |
| Test location | `validators/tests/<validator_name>/` with `spend.ak` and `mint.ak` |
| Spec location | `spec/<N>_<validator>/spend+mint.md` with numbered directories |

## Code Map

| Directory | Purpose | Key Files |
|-----------|---------|-----------|
| `validators/vault/` | Core vault validator (spend + mint) | `spend_mint.ak` |
| `validators/l1_deposit_intent/` | L1 deposit intent validator | `spend_and_mint.ak` |
| `validators/l1_withdrawal_intent/` | L1 withdrawal intent validator | `spend_and_mint.ak` |
| `validators/l2_deposit_intent/` | L2 deposit intent validator | `spend_and_mint.ak` |
| `validators/l2_withdrawal_intent/` | L2 withdrawal intent validator | `spend_and_mint.ak` |
| `lib/` | Shared types and utilities | `types.ak`, `deposit_utils.ak`, `withdraw_utils.ak` |
| `spec/` | Validator specifications | `0_vault/`, `1_l1_deposit_intent/`, etc. |
| `validators/tests/` | Test modules per validator | `vault/`, `l1_deposit_intent/`, etc. |

## Flow

`User -> Intent UTxO (mint) -> Operator Batch (spend) -> Vault State + MPF Trie Update`

## Key Files

| File | Why It Matters |
|------|----------------|
| `lib/types.ak` | All shared types: VaultDatum, intents, redeemers, LPMPFAction |
| `validators/vault/spend_mint.ak` | Core vault logic, start here for vault operations |
| `lib/deposit_utils.ak` | Batched deposit processing with MPF trie transitions |
| `lib/withdraw_utils.ak` | Withdrawal processing with fee calculation and MPF updates |
| `lib/price_oracle_utils.ak` | Oracle message verification and USD price conversion |
| `lib/utils.ak` | Vault/oracle lookup, signature verification, mint checks |

## Invariants

| Rule | If Violated |
|------|-------------|
| LP rounds DOWN for deposits (`usd * total_lp / balance`) | Depositor receives more LP than entitled |
| Fee rounds UP via `ceil_div` for withdrawals | Operator fee underpaid |
| `VaultDatum.lp_merkle_root` is single source of truth for LP positions | LP balances become inconsistent |
| Oracle message includes consumed `utxo_ref` for freshness | Stale prices can be replayed |

## Data Representations

| Internal | External | Converter | Notes |
|----------|----------|-----------|-------|
| `Value` (stdlib) | `MValue` (Pairs-based) | `deposit_utils.to_mvalue` | CBOR round-trip; needed for on-chain arithmetic |
| `LPRecordEntry {lp, cost}` | `ByteArray` (MPF value) | `cbor.serialise`/`cbor.deserialise` | Stored serialized in MPF trie |

## Code Dependencies

### This Repo Imports

| Package | Import Path | Purpose | Source |
|---------|-------------|---------|--------|
| stdlib | `aiken-lang/stdlib` v2.2.0 | Core Aiken primitives | github |
| vodka | `sidan-lab/vodka` 0.1.22 | Transaction helpers (`cocktail`) | github |
| deltadefi-scripts | `deltadefi-protocol/deltadefi-scripts` v1.0.0 | Shared types (`AppOracleDatum`) | github |
| merkle-patricia-forestry | `aiken-lang/merkle-patricia-forestry` 2.0.0 | MPF trie operations | github |

### Imported By (Downstream)

| Repo | Import Path | What They Use |
|------|-------------|---------------|
| Off-chain operator service | compiled validators from `plutus.json` | Builds and submits transactions against these validators |

Package exports: See `EXPORTS.md`

## Knowledge Base

Read `~/knowledge/index.md` first for any product/design question. Follow wikilinks to specific files (e.g. `products/vault/index.md`). Only grep as a fallback.

| Command | Purpose |
|---------|---------|
| `/kb:search <query>` | Search knowledge base for specs and design docs |

## Project Management

| Property | Value |
|----------|-------|
| Provider | `notion` |
| Product Space | `228c299fe9af809389d0d529ea2a3e60` |
| Task Database | `7e54d78c281249c3b2934beb8dbe953d` |
| Task Pattern | `DD-XXXX` |

## Workflow Commands

| Command | Purpose |
|---------|---------|
| `/pm:get-task` | Fetch task (provider-aware) |
| `/ctx:update` | Update Claude context files |
| `/dev:analyze` | Cross-repo dependency analysis |

## PM Permissions

| Tool | Permission |
|------|------------|
| `notion-fetch`, `notion-search`, `notion-get-*` | allowed |
| `notion-update-page`, `notion-create-pages` | confirm |
| `notion-move-pages`, delete operations | forbidden |

## GitHub MCP

| Organization | Tool Prefix |
|--------------|-------------|
| deltadefi-protocol | `mcp__github-deltadefi-protocol__*` |
| sidan-lab | `mcp__github-sidan-lab__*` |

## Config

| Key | Value |
|-----|-------|
| Cache | `.claude/session/` |
| Gitignore | `.claude/session/` |
