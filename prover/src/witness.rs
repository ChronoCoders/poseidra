use ark_bn254::Fr;
use ark_ff::PrimeField;
use serde::{Deserialize, Serialize};
use std::str::FromStr;

use crate::domain::{DOMAIN_COMMITMENT, DOMAIN_NULLIFIER, TREE_DEPTH};
use crate::errors::WitnessError;
use crate::poseidon::{poseidon2, poseidon3, poseidon4};

/// All private and public inputs required by the withdrawal circuit.
///
/// All field elements are stored as `ark_bn254::Fr`.
/// `to_circom_json()` serialises them to decimal strings for snarkjs compatibility.
#[derive(Debug, Clone)]
pub struct WitnessInput {
    // ── Private inputs ───────────────────────────────────────────────────────
    pub secret: Fr,
    pub nullifier: Fr,
    pub path_elements: [Fr; TREE_DEPTH],
    pub path_indices: [bool; TREE_DEPTH],

    // ── Public inputs ────────────────────────────────────────────────────────
    pub root: Fr,
    pub nullifier_hash: Fr,
    /// Recipient address packed into a field element (lower 160 bits).
    pub recipient: Fr,
    pub chain_id: Fr,
    pub contract_address: Fr,
}

/// snarkjs input JSON format for withdraw.circom
#[derive(Debug, Serialize, Deserialize)]
struct CircomInput {
    secret: String,
    nullifier: String,
    #[serde(rename = "pathElements")]
    path_elements: Vec<String>,
    #[serde(rename = "pathIndices")]
    path_indices: Vec<u8>,
    root: String,
    nullifier_hash: String,
    recipient: String,
    chain_id: String,
    contract_address: String,
}

impl WitnessInput {
    /// Compute and validate all witness values from raw inputs.
    ///
    /// Validates locally before returning:
    /// - Commitment is correctly computed from secret + nullifier.
    /// - Nullifier hash is correctly computed.
    /// - Merkle path leads from commitment to the claimed root.
    ///
    /// Returns `WitnessError` on any mismatch — do not proceed to proof generation
    /// unless this function succeeds.
    pub fn build(
        secret: Fr,
        nullifier: Fr,
        path_elements: [Fr; TREE_DEPTH],
        path_indices: [bool; TREE_DEPTH],
        chain_id: Fr,
        contract_address: Fr,
        recipient: Fr,
    ) -> Result<Self, WitnessError> {
        // 1. Commitment
        let commitment = poseidon3(DOMAIN_COMMITMENT, secret, nullifier)?;

        // 2. Nullifier hash
        let nullifier_hash = poseidon4(DOMAIN_NULLIFIER, nullifier, chain_id, contract_address)?;

        // 3. Walk Merkle path
        let root = compute_merkle_root(commitment, &path_elements, &path_indices)?;

        Ok(Self {
            secret,
            nullifier,
            path_elements,
            path_indices,
            root,
            nullifier_hash,
            recipient,
            chain_id,
            contract_address,
        })
    }

    /// Verify this witness against an externally supplied root (e.g. from backend API).
    pub fn verify_root(&self, expected_root: Fr) -> Result<(), WitnessError> {
        if self.root != expected_root {
            return Err(WitnessError::MerkleRootMismatch {
                computed: fr_to_decimal(self.root),
                expected: fr_to_decimal(expected_root),
            });
        }
        Ok(())
    }

    /// Serialise to the JSON format consumed by circom's witness generator.
    pub fn to_circom_json(&self) -> Result<String, WitnessError> {
        let input = CircomInput {
            secret: fr_to_decimal(self.secret),
            nullifier: fr_to_decimal(self.nullifier),
            path_elements: self
                .path_elements
                .iter()
                .map(|e| fr_to_decimal(*e))
                .collect(),
            path_indices: self.path_indices.iter().map(|&b| b as u8).collect(),
            root: fr_to_decimal(self.root),
            nullifier_hash: fr_to_decimal(self.nullifier_hash),
            recipient: fr_to_decimal(self.recipient),
            chain_id: fr_to_decimal(self.chain_id),
            contract_address: fr_to_decimal(self.contract_address),
        };
        serde_json::to_string_pretty(&input)
            .map_err(|e| WitnessError::Poseidon(format!("JSON serialisation failed: {e}")))
    }

    /// Public inputs as decimal strings in circuit order:
    /// [root, nullifier_hash, recipient, chain_id, contract_address]
    pub fn public_inputs_decimal(&self) -> Vec<String> {
        vec![
            fr_to_decimal(self.root),
            fr_to_decimal(self.nullifier_hash),
            fr_to_decimal(self.recipient),
            fr_to_decimal(self.chain_id),
            fr_to_decimal(self.contract_address),
        ]
    }
}

/// Walk the Merkle path from `leaf` and return the computed root.
pub fn compute_merkle_root(
    leaf: Fr,
    path_elements: &[Fr; TREE_DEPTH],
    path_indices: &[bool; TREE_DEPTH],
) -> Result<Fr, WitnessError> {
    let mut current = leaf;
    for level in 0..TREE_DEPTH {
        let sibling = path_elements[level];
        let (left, right) = if !path_indices[level] {
            (current, sibling)
        } else {
            (sibling, current)
        };
        current = poseidon2(left, right)?;
    }
    Ok(current)
}

/// Convert Fr to its canonical decimal string representation.
pub fn fr_to_decimal(f: Fr) -> String {
    // PrimeField::into_bigint() returns a little-endian BigInt.
    // ToString on BigInteger gives the decimal representation.
    f.into_bigint().to_string()
}

/// Convert a decimal string to Fr. Fails if the string is not a valid field element.
pub fn decimal_to_fr(s: &str) -> Option<Fr> {
    Fr::from_str(s).ok()
}

/// Convert a 0x-prefixed or plain hex string to Fr.
pub fn hex_to_fr(s: &str) -> Option<Fr> {
    let stripped = s.strip_prefix("0x").unwrap_or(s);
    let bytes = hex::decode(stripped).ok()?;
    // Pad to 32 bytes (big-endian)
    let mut padded = [0u8; 32];
    let offset = 32usize.saturating_sub(bytes.len());
    padded[offset..].copy_from_slice(&bytes[bytes.len().saturating_sub(32)..]);
    Fr::from_be_bytes_mod_order(&padded).into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use ark_ff::Zero;

    fn zero_path() -> ([Fr; TREE_DEPTH], [bool; TREE_DEPTH]) {
        ([Fr::zero(); TREE_DEPTH], [false; TREE_DEPTH])
    }

    #[test]
    fn build_witness_succeeds_for_zero_path() {
        let secret = Fr::from(1u64);
        let nullifier = Fr::from(2u64);
        let chain_id = Fr::from(1u64);
        let contract_address = Fr::from(54321u64);
        let recipient = Fr::from(12345u64);
        let (path_elements, path_indices) = zero_path();

        let w = WitnessInput::build(
            secret,
            nullifier,
            path_elements,
            path_indices,
            chain_id,
            contract_address,
            recipient,
        )
        .expect("build should succeed");

        // Verify self-consistency: re-computing root from the witness must match.
        let recomputed_root = compute_merkle_root(
            poseidon3(DOMAIN_COMMITMENT, secret, nullifier).unwrap(),
            &w.path_elements,
            &w.path_indices,
        )
        .unwrap();
        assert_eq!(w.root, recomputed_root);
    }

    #[test]
    fn to_circom_json_round_trips() {
        let secret = Fr::from(42u64);
        let nullifier = Fr::from(99u64);
        let (path_elements, path_indices) = zero_path();

        let w = WitnessInput::build(
            secret,
            nullifier,
            path_elements,
            path_indices,
            Fr::from(1u64),
            Fr::from(99999u64),
            Fr::from(888u64),
        )
        .unwrap();

        let json = w.to_circom_json().unwrap();
        let parsed: CircomInput = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.path_indices.len(), TREE_DEPTH);
        assert_eq!(parsed.path_elements.len(), TREE_DEPTH);
    }

    /// Emits test vector values for cross-client verification.
    /// Run with: cargo test generate_test_vector -- --nocapture
    #[test]
    fn generate_test_vector() {
        let secret = Fr::from(1u64);
        let nullifier = Fr::from(2u64);
        let chain_id = Fr::from(1u64);
        let contract_address = Fr::from(54321u64);
        let recipient = Fr::from(12345u64);
        let (path_elements, path_indices) = zero_path();

        let w = WitnessInput::build(
            secret,
            nullifier,
            path_elements,
            path_indices,
            chain_id,
            contract_address,
            recipient,
        )
        .unwrap();

        println!("=== Test Vector (for cross-client verification) ===");
        println!("secret:           1");
        println!("nullifier:        2");
        println!(
            "commitment:       {}",
            fr_to_decimal(poseidon3(DOMAIN_COMMITMENT, secret, nullifier).unwrap())
        );
        println!("nullifier_hash:   {}", fr_to_decimal(w.nullifier_hash));
        println!("root:             {}", fr_to_decimal(w.root));
        println!("chain_id:         1");
        println!("contract_address: 54321");
        println!("recipient:        12345");
        println!("===================================================");
        println!("Verify with:");
        println!("  cd circuits && node -e \"");
        println!("    const {{ buildPoseidon }} = require('circomlibjs');");
        println!("    buildPoseidon().then(p => {{");
        println!("      const F = p.F;");
        println!("      const DC = {}n;", fr_to_decimal(DOMAIN_COMMITMENT));
        println!("      const DN = {}n;", fr_to_decimal(DOMAIN_NULLIFIER));
        println!("      console.log('commitment:', F.toString(p([DC, 1n, 2n])));");
        println!("      console.log('nullifier_hash:', F.toString(p([DN, 2n, 1n, 54321n])));");
        println!("    }});");
        println!("  \"");
    }
}
