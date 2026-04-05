//! Poseidra Prover
//!
//! Public API for generating withdrawal proofs.
//!
//! # Usage
//!
//! ```text
//! let key = ProvingKey::load(Path::new("build/circuits")).unwrap();
//! let proof = generate_proof(&key, secret, nullifier, path_elements,
//!                            path_indices, chain_id, contract_address, recipient).unwrap();
//! ```

pub mod domain;
pub mod errors;
pub mod poseidon;
pub mod prover;
pub mod witness;

pub use errors::{ParameterError, ProofError, WitnessError};
pub use prover::{Proof, ProvingKey};
pub use witness::{WitnessInput, compute_merkle_root, fr_to_decimal, hex_to_fr};

use ark_bn254::Fr;
/// Generate a PLONK withdrawal proof.
///
/// This is the primary entrypoint. It:
/// 1. Builds and validates the witness (Poseidon hashing, Merkle path check).
/// 2. Generates a PLONK + KZG proof via snarkjs.
/// 3. Returns the serialised proof + public signals.
///
/// # Errors
/// Returns `ProofError` if witness validation fails or proof generation fails.
/// No secret material (secret, nullifier) appears in error messages or logs.
#[allow(clippy::too_many_arguments)]
pub fn generate_proof(
    key: &ProvingKey,
    secret: Fr,
    nullifier: Fr,
    path_elements: [Fr; domain::TREE_DEPTH],
    path_indices: [bool; domain::TREE_DEPTH],
    chain_id: Fr,
    contract_address: Fr,
    recipient: Fr,
) -> Result<Proof, ProofError> {
    let witness = WitnessInput::build(
        secret,
        nullifier,
        path_elements,
        path_indices,
        chain_id,
        contract_address,
        recipient,
    )?;

    prover::prove(key, &witness)
}
