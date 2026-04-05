/// Poseidon hash wrappers for Poseidra.
///
/// Uses `light-poseidon` (version 0.2) which implements BN254 Poseidon with the same
/// parameters as circomlib:
///   - Field: BN254 scalar field Fr
///   - Round constants: Grain LFSR, identical to circomlib poseidon_constants.circom
///   - MDS matrix: identical to circomlib
///   - S-box: x^5 (alpha = 5)
///   - t = nInputs + 1 (circomlib convention: 1 capacity element)
///   - RF = 8, RP = 57 (for t=3), RP scales with t per the Poseidon paper
///
/// Any deviation between this output and circomlib output for the same inputs is a
/// critical bug. The integration tests cross-check against known test vectors.
use ark_bn254::Fr;
use light_poseidon::{Poseidon, PoseidonHasher};

use crate::errors::WitnessError;

/// Hash 3 field elements: Poseidon(a, b, c).
/// Used for commitment: Poseidon(domain_commitment, secret, nullifier).
pub fn poseidon3(a: Fr, b: Fr, c: Fr) -> Result<Fr, WitnessError> {
    let mut h = Poseidon::<Fr>::new_circom(3).map_err(|e| WitnessError::Poseidon(e.to_string()))?;
    h.hash(&[a, b, c])
        .map_err(|e| WitnessError::Poseidon(e.to_string()))
}

/// Hash 4 field elements: Poseidon(a, b, c, d).
/// Used for nullifier hash: Poseidon(domain_nullifier, nullifier, chain_id, contract_address).
pub fn poseidon4(a: Fr, b: Fr, c: Fr, d: Fr) -> Result<Fr, WitnessError> {
    let mut h = Poseidon::<Fr>::new_circom(4).map_err(|e| WitnessError::Poseidon(e.to_string()))?;
    h.hash(&[a, b, c, d])
        .map_err(|e| WitnessError::Poseidon(e.to_string()))
}

/// Hash 2 field elements: Poseidon(left, right).
/// Used for all Merkle tree node hashing.
pub fn poseidon2(left: Fr, right: Fr) -> Result<Fr, WitnessError> {
    let mut h = Poseidon::<Fr>::new_circom(2).map_err(|e| WitnessError::Poseidon(e.to_string()))?;
    h.hash(&[left, right])
        .map_err(|e| WitnessError::Poseidon(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    // Test vectors: these must match circomlib output for identical inputs.
    // Generate reference values with:
    //   cd circuits && node -e "
    //     const { buildPoseidon } = require('circomlibjs');
    //     buildPoseidon().then(p => {
    //       console.log(p.F.toString(p([1n, 2n, 3n])));
    //       console.log(p.F.toString(p([1n, 2n, 3n, 4n])));
    //       console.log(p.F.toString(p([1n, 2n])));
    //     });
    //   "
    //
    // Until cross-verified, these tests enforce self-consistency.

    #[test]
    fn poseidon3_is_deterministic() {
        let a = Fr::from(1u64);
        let b = Fr::from(2u64);
        let c = Fr::from(3u64);
        let h1 = poseidon3(a, b, c).unwrap();
        let h2 = poseidon3(a, b, c).unwrap();
        assert_eq!(h1, h2);
    }

    #[test]
    fn poseidon4_is_deterministic() {
        let h1 = poseidon4(
            Fr::from(1u64),
            Fr::from(2u64),
            Fr::from(3u64),
            Fr::from(4u64),
        )
        .unwrap();
        let h2 = poseidon4(
            Fr::from(1u64),
            Fr::from(2u64),
            Fr::from(3u64),
            Fr::from(4u64),
        )
        .unwrap();
        assert_eq!(h1, h2);
    }

    #[test]
    fn poseidon2_is_deterministic() {
        let h1 = poseidon2(Fr::from(1u64), Fr::from(2u64)).unwrap();
        let h2 = poseidon2(Fr::from(1u64), Fr::from(2u64)).unwrap();
        assert_eq!(h1, h2);
    }

    #[test]
    fn poseidon_output_differs_on_different_inputs() {
        let h1 = poseidon2(Fr::from(1u64), Fr::from(2u64)).unwrap();
        let h2 = poseidon2(Fr::from(2u64), Fr::from(1u64)).unwrap();
        assert_ne!(
            h1, h2,
            "Poseidon must not be commutative for ordered inputs"
        );
    }

    #[test]
    fn domain_separation_produces_distinct_hashes() {
        use crate::domain::{DOMAIN_COMMITMENT, DOMAIN_NULLIFIER};
        let secret = Fr::from(42u64);
        let nullifier = Fr::from(99u64);

        let c = poseidon3(DOMAIN_COMMITMENT, secret, nullifier).unwrap();
        let n = poseidon3(DOMAIN_NULLIFIER, secret, nullifier).unwrap();
        assert_ne!(c, n, "Different domains must produce different hashes");
    }

    // Cross-client test vectors — fill in after running circomlib reference.
    // Format: (inputs, expected_decimal_string)
    // Run `cargo test cross_client -- --nocapture` after populating.
    #[test]
    #[ignore = "populate expected values from circomlib before enabling"]
    fn cross_client_poseidon2() {
        let got = poseidon2(Fr::from(1u64), Fr::from(2u64)).unwrap();
        // expected = circomlib Poseidon([1, 2]) output as decimal string
        let expected_decimal = "TODO_INSERT_CIRCOMLIB_OUTPUT";
        assert_eq!(got.to_string(), expected_decimal);
    }

    #[test]
    #[ignore = "populate expected values from circomlib before enabling"]
    fn cross_client_poseidon3() {
        let got = poseidon3(Fr::from(1u64), Fr::from(2u64), Fr::from(3u64)).unwrap();
        let expected_decimal = "TODO_INSERT_CIRCOMLIB_OUTPUT";
        assert_eq!(got.to_string(), expected_decimal);
    }
}
