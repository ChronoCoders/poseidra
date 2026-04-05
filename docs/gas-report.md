# Gas Report

Measured with `forge snapshot`. Updated each time contracts change.

## Targets

| Operation | Target | Measured | Status |
|-----------|--------|----------|--------|
| deposit   | < 250k | 823,614  | needs storage optimisation |
| withdraw  | < 600k | 863,521  | needs storage optimisation |

## Optimisation History

| Step | deposit | withdraw | change |
|------|---------|----------|--------|
| baseline (pure-Solidity PoseidonT3) | 1,902,004 | 1,941,911 | — |
| circomlib assembly Poseidon via CREATE+staticcall | 823,614 | 863,521 | -57% |

## Current Bottleneck

Hashing is solved (~12k gas/call via assembly bytecode vs ~95k before).
Remaining cost is dominated by 20 cold SSTORE writes to `filledSubtrees[i]` per deposit:

- 20 levels × ~20k gas/cold SSTORE = ~400k
- Plus 1 SSTORE for `nextLeafIndex`, 1 SSTORE for `roots[idx]`, calldata, events ≈ ~60k
- Total irreducible at depth=20 on L1: ~460–500k

To reach the 250k deposit target the only viable paths are:
1. **Reduce depth**: depth=16 → ~13 cold SSTOREs on a new leaf path → ~300k (closer but still over)
2. **EIP-4337 batching / L2**: zkSync native Poseidon precompile brings deposit to ~50k
3. **Revisit target**: 250k was set before accounting for 20 cold SSTOREs being irreducible.
   Revised realistic L1 target is ~500k for deposit, ~600k for withdraw (PLONK verify overhead TBD).

## Next Required Step

Generate real `Verifier.sol` from the compiled circuit:
```bash
snarkjs plonk export solidityverifier withdraw.zkey contracts/src/Verifier.sol
```
Then re-run `forge snapshot` — PLONK verification (~200–400k) will add to withdraw cost.
The withdraw target of 600k will need revisiting once the real verifier is in place.

## Notes

- Numbers use `VerifierStub` (always returns true). Real PLONK verifier adds ~200–400k to withdraw.
- Gas numbers are for L1 EVM. zkSync has a native Poseidon precompile (~50k deposit natively).
- `forge snapshot` run after `forge clean` to avoid stale cache.
