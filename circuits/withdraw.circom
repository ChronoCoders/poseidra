pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/mux1.circom";
include "constants.circom";

// MerklePathVerifier
//
// Verifies that a leaf exists in a Merkle tree of depth TREE_DEPTH() given
// the sibling path. Uses Poseidon(left, right) for each node — 2 inputs,
// t=3 internally (circomlib convention: t = nInputs + 1).

template MerklePathVerifier(depth) {
    signal input  leaf;
    signal input  pathElements[depth];
    signal input  pathIndices[depth];  // 0 = leaf is left child, 1 = leaf is right child
    signal output root;

    component hashers[depth];
    component mux[depth];

    signal nodes[depth + 1];
    nodes[0] <== leaf;

    for (var i = 0; i < depth; i++) {
        // Enforce that pathIndices[i] is boolean
        pathIndices[i] * (1 - pathIndices[i]) === 0;

        mux[i] = MultiMux1(2);
        // If pathIndices[i] == 0: left = nodes[i], right = pathElements[i]
        // If pathIndices[i] == 1: left = pathElements[i], right = nodes[i]
        mux[i].c[0][0] <== nodes[i];
        mux[i].c[1][0] <== pathElements[i];
        mux[i].c[0][1] <== pathElements[i];
        mux[i].c[1][1] <== nodes[i];
        mux[i].s       <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== mux[i].out[0];
        hashers[i].inputs[1] <== mux[i].out[1];

        nodes[i + 1] <== hashers[i].out;
    }

    root <== nodes[depth];
}

// WithdrawCircuit
//
// Main withdrawal proof. Proves:
//   1. Knowledge of secret and nullifier whose commitment is a leaf in the tree.
//   2. The nullifier hash is correctly computed and bound to this chain/contract.
//   3. The Merkle inclusion path is valid against a known root.
//
// Private inputs:
//   secret, nullifier, pathElements[20], pathIndices[20]
//
// Public inputs:
//   root, nullifier_hash, recipient, chain_id, contract_address

template WithdrawCircuit(depth) {
    // Private
    signal input secret;
    signal input nullifier;
    signal input pathElements[depth];
    signal input pathIndices[depth];

    // Public
    signal input root;
    signal input nullifier_hash;
    signal input recipient;
    signal input chain_id;
    signal input contract_address;

    // 1. Commitment hash
    component commitmentHasher = Poseidon(3);
    commitmentHasher.inputs[0] <== DOMAIN_COMMITMENT();
    commitmentHasher.inputs[1] <== secret;
    commitmentHasher.inputs[2] <== nullifier;

    // 2. Nullifier hash
    component nullifierHasher = Poseidon(4);
    nullifierHasher.inputs[0] <== DOMAIN_NULLIFIER();
    nullifierHasher.inputs[1] <== nullifier;
    nullifierHasher.inputs[2] <== chain_id;
    nullifierHasher.inputs[3] <== contract_address;

    // Enforce claimed nullifier_hash matches computed value
    nullifierHasher.out === nullifier_hash;

    // 3. Merkle inclusion
    component merkle = MerklePathVerifier(depth);
    merkle.leaf              <== commitmentHasher.out;
    for (var i = 0; i < depth; i++) {
        merkle.pathElements[i] <== pathElements[i];
        merkle.pathIndices[i]  <== pathIndices[i];
    }

    // Enforce claimed root matches computed root
    merkle.root === root;

    // Bind recipient to the proof so it cannot be changed post-generation.
    // This is a no-op constraint that forces recipient into the witness.
    signal recipientSquared;
    recipientSquared <== recipient * recipient;
}

component main {
    public [root, nullifier_hash, recipient, chain_id, contract_address]
} = WithdrawCircuit(20);
