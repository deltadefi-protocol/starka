# Starka TODO

## Missing Tests - Pending External Data Preparation

### Merkle Proof Tests
The following tests require pre-computed merkle proof data:

- [ ] `validators/tests/deposit_utils/process_batch.ak` - All tests commented out
  - `process_batch_normal()`
  - `process_batch_insufficient_inputs()`
  - `process_batch_excessive_indices()`
  - `process_batch_incorrect_outputs()`
  - L2 variants

- [ ] `validators/tests/withdraw_utils/process_batch.ak` - All tests commented out
  - `process_batch_normal()`
  - `process_batch_insufficient_inputs()`
  - `process_batch_excessive_indices()`
  - `process_batch_incorrect_outputs()`
  - L2 variants

### Price Message / Oracle Message Tests
The following tests fail due to missing mock oracle message data:

- [ ] `validators/tests/l1_deposit_intent/burn_intent.ak`
- [ ] `validators/tests/l1_withdrawal_intent/burn_intent.ak`
- [ ] `validators/tests/vault_oracle/mint.ak`
- [ ] `validators/tests/vault_oracle/spend.ak`
  - L1InitialDeposit tests need price message with prices matching `mock_create_vault_deposit_m_value` (1000 ADA + 1000 USDM)

### Data Preparation Required

1. **Merkle Proof Data**
   - MPF (Merkle Patricia Forestry) proofs for insert/update/delete operations
   - Initial root, intermediate roots, final root for batched operations
   - SharesRecordEntry data with shares and total_deposited

2. **Oracle Message Data**
   - Signed price messages with valid signatures
   - `hydra_node_pub_keys` verification data
   - Price pairs for supported assets

## Notes

- Mock data should be generated from actual MPF library operations
- Oracle messages require cryptographic signatures matching `hydra_node_pub_keys`
