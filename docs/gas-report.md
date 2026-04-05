# Gas Report

Measured with `forge snapshot`. Updated each time contracts change.

## Targets

| Operation | Target | Measured | Status |
|-----------|--------|----------|--------|
| deposit   | < 250k | 1,902,004 | ❌ needs assembly Poseidon |
| withdraw  | < 600k | 1,941,911 | ❌ needs assembly Poseidon |

## Current Bottleneck

The Merkle tree insertion calls PoseidonT3.hash 20 times (one per level, depth=20).
Each call runs 65 permutation rounds in pure Solidity — even fully inlined this costs
~95k gas per call × 20 = ~1.9M gas.

Minimum theoretical cost for 20 Poseidon calls in assembly:
  ~12k gas/call × 20 = 240k (just above the 250k target after adding storage writes)

## Required Optimization

Replace PoseidonT3.sol with an assembly-optimized implementation.
The circomlib `poseidon_gencontract.js` generates EVM bytecode that achieves
~12k gas per Poseidon(2) call. Pattern:

1. Generate EVM bytecode: `node scripts/generate_poseidon_sol.js --bytecode`
2. Deploy as standalone `PoseidonHasher` contract (constructor stores bytecode)
3. MerkleTree calls hasher via `staticcall`
4. Re-run `forge snapshot` and verify both targets are met

## Notes

- These numbers use `VerifierStub` (always returns true). The real Verifier.sol
  will add ~200-400k gas to withdraw from on-chain PLONK verification.
  Withdraw target of 600k may need revisiting once Verifier.sol is generated.
- Gas numbers are for L1 EVM. zkSync has a native Poseidon precompile which
  would bring deposit cost to ~50k gas natively.
