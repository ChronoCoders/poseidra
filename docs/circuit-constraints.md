# Circuit Constraint Counts

Populated by `scripts/compile.sh`. Run `bash scripts/compile.sh` to update.

## Target

| Circuit     | Target      | Status  |
|-------------|-------------|---------|
| withdraw    | 2,300–2,600 | pending |

## Expected Breakdown (withdraw.circom, depth=20)

| Component                         | Approx Constraints |
|-----------------------------------|--------------------|
| Commitment: Poseidon(3 inputs)    | ~340               |
| Nullifier hash: Poseidon(4 inputs)| ~430               |
| Merkle path: 20 × Poseidon(2)     | ~20 × 90 = ~1,800  |
| Boolean checks (20 pathIndices)   | 20                 |
| **Total**                         | **~2,590**         |

Poseidon(n) internal state size t = n+1. Constraint count per call scales with t.
Actual counts must be measured and recorded here after each compile.

## Recorded Counts

<!-- snarkjs r1cs info output appended here by compile.sh -->
