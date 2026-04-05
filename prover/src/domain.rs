use ark_bn254::Fr;
use ark_ff::MontFp;

// Domain separation constants for Poseidra.
//
// Derivation: SHA-256(<domain_string>) mod BN254_SCALAR_PRIME
//   DOMAIN_COMMITMENT = SHA-256("poseidra.commitment.v1") mod p
//                     = 0x0e2b9afab83eb22667534fa5a9f05318662a0779bec0ed43e9f3509bda5ca9dc
//                     = 6409423932278525761570111016876651519417137198264293413507906025855764965852
//
//   DOMAIN_NULLIFIER   = SHA-256("poseidra.nullifier.v1") mod p
//                     = 0x106b02b60c19bea639871dc2ce12726a638d83663a6c74fd976d1e3358da7f28
//                     = 7426076924740874604926435454302484814870001900101103709475188478574790868776
//
// These values MUST be identical in:
//   - circuits/constants.circom
//   - prover/src/domain.rs          (this file)
//   - contracts/src/lib/Poseidon.sol
//
// Changing these values breaks cross-client compatibility. Coordinate with
// solidity-builder before any update.

pub const DOMAIN_COMMITMENT: Fr =
    MontFp!("6409423932278525761570111016876651519417137198264293413507906025855764965852");

pub const DOMAIN_NULLIFIER: Fr =
    MontFp!("7426076924740874604926435454302484814870001900101103709475188478574790868776");

/// Merkle tree depth — must match MerkleTree.sol and circuits/constants.circom.
pub const TREE_DEPTH: usize = 20;

#[cfg(test)]
mod tests {
    use super::*;
    use ark_ff::BigInteger;
    use ark_ff::PrimeField;

    #[test]
    fn domain_constants_are_nonzero_and_distinct() {
        assert_ne!(DOMAIN_COMMITMENT, Fr::from(0u64));
        assert_ne!(DOMAIN_NULLIFIER, Fr::from(0u64));
        assert_ne!(DOMAIN_COMMITMENT, Fr::from(1u64));
        assert_ne!(DOMAIN_NULLIFIER, Fr::from(1u64));
        assert_ne!(DOMAIN_COMMITMENT, DOMAIN_NULLIFIER);
    }

    #[test]
    fn domain_constants_match_expected_hex() {
        let commitment_bytes = DOMAIN_COMMITMENT.into_bigint().to_bytes_be();
        let nullifier_bytes = DOMAIN_NULLIFIER.into_bigint().to_bytes_be();

        let commitment_hex = hex::encode(&commitment_bytes);
        let nullifier_hex = hex::encode(&nullifier_bytes);

        // Padded to 64 hex chars (32 bytes)
        assert_eq!(
            commitment_hex,
            "0e2b9afab83eb22667534fa5a9f05318662a0779bec0ed43e9f3509bda5ca9dc",
            "DOMAIN_COMMITMENT hex mismatch — cross-check with circuits/constants.circom"
        );
        assert_eq!(
            nullifier_hex,
            "106b02b60c19bea639871dc2ce12726a638d83663a6c74fd976d1e3358da7f28",
            "DOMAIN_NULLIFIER hex mismatch — cross-check with circuits/constants.circom"
        );
    }
}
