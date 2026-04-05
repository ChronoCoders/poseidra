pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "constants.circom";

// NullifierHasher
//
// Computes the on-chain nullifier hash that marks a commitment as spent.
// nullifier_hash = Poseidon(DOMAIN_NULLIFIER, nullifier, chain_id, contract_address)
//
// chain_id and contract_address bind the nullifier to a specific deployment,
// preventing cross-chain and cross-contract replay.

template NullifierHasher() {
    signal input  nullifier;
    signal input  chain_id;
    signal input  contract_address;
    signal output nullifier_hash;

    component hasher = Poseidon(4);
    hasher.inputs[0] <== DOMAIN_NULLIFIER();
    hasher.inputs[1] <== nullifier;
    hasher.inputs[2] <== chain_id;
    hasher.inputs[3] <== contract_address;

    nullifier_hash <== hasher.out;
}

component main {
    public [chain_id, contract_address]
} = NullifierHasher();
