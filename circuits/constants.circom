pragma circom 2.1.6;

// Domain separation constants for Poseidra.
//
// Derivation: SHA-256(<domain_string>) mod BN254_SCALAR_PRIME
// Domain strings: "poseidra.commitment.v1", "poseidra.nullifier.v1"
//
// These values MUST be identical in:
//   - circuits/constants.circom          (this file)
//   - prover/src/domain.rs
//   - contracts/src/lib/Poseidon.sol
//
// Do NOT change without updating all three locations and rerunning cross-client tests.

// SHA-256("poseidra.commitment.v1") mod p
// = 0x0e2b9afab83eb22667534fa5a9f05318662a0779bec0ed43e9f3509bda5ca9dc
function DOMAIN_COMMITMENT() {
    return 6409423932278525761570111016876651519417137198264293413507906025855764965852;
}

// SHA-256("poseidra.nullifier.v1") mod p
// = 0x106b02b60c19bea639871dc2ce12726a638d83663a6c74fd976d1e3358da7f28
function DOMAIN_NULLIFIER() {
    return 7426076924740874604926435454302484814870001900101103709475188478574790868776;
}

// Merkle tree depth — must match MerkleTree.sol and prover::witness
function TREE_DEPTH() {
    return 20;
}
