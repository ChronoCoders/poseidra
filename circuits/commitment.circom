pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "constants.circom";

// CommitmentHasher
//
// Proves knowledge of (secret, nullifier) for a given commitment.
// commitment = Poseidon(DOMAIN_COMMITMENT, secret, nullifier)
//
// The domain constant occupies the first input slot, enforcing domain separation
// between commitment hashes and all other Poseidon uses in this protocol.

template CommitmentHasher() {
    signal input  secret;
    signal input  nullifier;
    signal output commitment;

    component hasher = Poseidon(3);
    hasher.inputs[0] <== DOMAIN_COMMITMENT();
    hasher.inputs[1] <== secret;
    hasher.inputs[2] <== nullifier;

    commitment <== hasher.out;
}

component main { public [] } = CommitmentHasher();
