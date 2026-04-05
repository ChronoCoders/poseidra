# Circuit Constraint Counts

Populated by `scripts/compile.sh`. Run `bash scripts/compile.sh` to update.

## Measured (withdraw.circom, depth=20)

| Metric                 | Value  |
|------------------------|--------|
| Curve                  | BN-128 |
| Non-linear constraints | 5,413  |
| Wires                  | 5,439  |
| Private inputs         | 42     |
| Public inputs          | 5      |
| Labels                 | 17,693 |
| PLONK constraints      | 59,096 |
| ptau required          | ≥ 16 (2^16 = 65,536 ≥ 59,096) |

## Public Signal Order

Circuit output order (must match Solidity verifier and Rust prover):

```
pubSignals[0] = root
pubSignals[1] = nullifier_hash
pubSignals[2] = recipient
pubSignals[3] = chain_id
pubSignals[4] = contract_address
```

## Component Breakdown

| Component                               | Approx Constraints |
|-----------------------------------------|--------------------|
| Commitment: Poseidon(domain, s, n)      | ~270 (t=4)         |
| Nullifier hash: Poseidon(domain,n,c,a)  | ~370 (t=5)         |
| Merkle path: 20 × Poseidon(l, r)        | 20 × ~240 = ~4,800 |
| Boolean checks (20 pathIndices)         | ~20                |
| **Total (measured)**                    | **5,413**          |

## Notes

- Initial estimate (2,300–2,600) was too low. circomlib Poseidon with t=3 uses ~240
  constraints/call (full + partial rounds × 2 multiplications each), not ~90.
- ptau 16 used for development. For production, replace with a public ceremony ptau
  (Hermez perpetual powers of tau, ptau 16 or higher).
- PLONK pads to next power of 2: 59,096 → 65,536 = 2^16.
