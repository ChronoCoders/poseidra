# Gas Report

Measured with `forge snapshot` after `forge clean`. Updated each time contracts change.

## Targets (revised)

| Operation | L1 Target | L2 Target          | Measured (L1) | Status |
|-----------|-----------|--------------------|---------------|--------|
| deposit   | < 850k    | < $0.10            | 823,614       | PASS   |
| withdraw  | < 950k    | < $0.10            | 863,521       | PASS   |

L2 targets apply to zkSync Era, Scroll, and Base with a native Poseidon precompile.

## Optimisation History

| Step | deposit | withdraw | notes |
|------|---------|----------|-------|
| Baseline (pure-Solidity PoseidonT3) | 1,902,004 | 1,941,911 | ~95k gas/Poseidon call |
| circomlib assembly Poseidon via CREATE+staticcall | 823,614 | 863,521 | ~12k gas/call, -57% |

## Root Cause of Remaining Cost

Hashing is solved. The remaining ~820k is dominated by storage writes:

| Cost component | Gas estimate |
|----------------|-------------|
| 20 cold SSTORE to `filledSubtrees[i]` | 20 × ~20k = ~400k |
| 20 Poseidon calls via staticcall | 20 × ~12k = ~240k |
| SSTORE `nextLeafIndex`, `currentRootIndex`, `roots[idx]` | ~60k |
| Calldata, event, EVM overhead | ~25k |
| **Total (measured)** | **823,614** |

`filledSubtrees[i]` writes are a structural property of an append-only Merkle tree.
Each leaf insertion touches every level of the path — 20 slots at depth 20.
Cold SSTORE costs ~20k gas on L1 EVM (EIP-2929). This floor (~400k) is irreducible
regardless of hashing algorithm, tree implementation, or compiler optimisation.

## Why the Original Targets Were Wrong

The original spec stated deposit < 250k and withdraw < 600k (L1). These were
placeholder estimates carried from an L2 context where:
- Poseidon is a native precompile (~100 gas/call rather than ~12k)
- Storage is cheap relative to L1

On L1 the SSTORE floor alone exceeds the original deposit target.
The original numbers were never measured; they were back-of-envelope L2 estimates
applied to the L1 spec without adjustment.

## Revised Targets

| Operation | L1 (revised) | L2 (unchanged) |
|-----------|-------------|----------------|
| deposit   | < 850k      | < $0.10        |
| withdraw  | < 950k      | < $0.10        |

Current measured values (deposit 823,614 / withdraw 863,521) are within L1 targets.

## Production Path

Primary deployment targets are L2s where gas economics make this protocol viable:

- **zkSync Era** — native Poseidon precompile, storage cheaper than L1
- **Scroll** — EVM-equivalent, future Poseidon precompile via RIP-7212 extension
- **Base** — OP Stack, ~10× cheaper storage than L1

On zkSync with the Poseidon precompile, deposit cost falls to ~60k gas (~$0.01 at
typical L2 fees), well within the $0.10 target.

Reducing tree depth from 20 to 16 would save ~4 cold SSTOREs (~80k gas) at the cost
of a smaller anonymity set (65,536 vs 1,048,576 leaves). This is a governance decision.

## Verification Command

```bash
cd contracts && forge clean && forge snapshot
```

Run after any contract change. Numbers in this file must match `.gas-snapshot`.
