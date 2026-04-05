/// Integration tests for poseidra-prover.
///
/// Full proof-generation tests require circuit artifacts built by `scripts/compile.sh`.
/// Run with: cargo test -- --include-ignored
///
/// Cross-client Poseidon tests require circomlib to be installed.
/// Run: cd circuits && npm install, then populate the expected vectors below.
use ark_bn254::Fr;
use ark_ff::Zero;
use poseidra_prover::{
    compute_merkle_root,
    domain::{DOMAIN_COMMITMENT, DOMAIN_NULLIFIER, TREE_DEPTH},
    fr_to_decimal,
    poseidon::{poseidon2, poseidon3, poseidon4},
    witness::WitnessInput,
};

fn zero_path() -> ([Fr; TREE_DEPTH], [bool; TREE_DEPTH]) {
    ([Fr::zero(); TREE_DEPTH], [false; TREE_DEPTH])
}

// ── Poseidon cross-client tests ──────────────────────────────────────────────
// Each `expected` value must be verified against circomlib output.
// Generate with:
//   cd circuits && node -e "
//     const { buildPoseidon } = require('circomlibjs');
//     buildPoseidon().then(p => {
//       const F = p.F;
//       console.log('p2(1,2):', F.toString(p([1n, 2n])));
//       console.log('p3(1,2,3):', F.toString(p([1n, 2n, 3n])));
//       console.log('p4(1,2,3,4):', F.toString(p([1n, 2n, 3n, 4n])));
//     });
//   "

#[test]
fn cross_client_poseidon2_matches_circomlib() {
    let got = poseidon2(Fr::from(1u64), Fr::from(2u64)).unwrap();
    assert_eq!(
        fr_to_decimal(got),
        "7853200120776062878684798364095072458815029376092732009249414926327459813530",
        "Poseidon2 mismatch vs circomlib"
    );
}

#[test]
fn cross_client_poseidon3_matches_circomlib() {
    let got = poseidon3(Fr::from(1u64), Fr::from(2u64), Fr::from(3u64)).unwrap();
    assert_eq!(
        fr_to_decimal(got),
        "6542985608222806190361240322586112750744169038454362455181422643027100751666",
        "Poseidon3 mismatch vs circomlib"
    );
}

#[test]
fn cross_client_poseidon4_matches_circomlib() {
    let got = poseidon4(
        Fr::from(1u64),
        Fr::from(2u64),
        Fr::from(3u64),
        Fr::from(4u64),
    )
    .unwrap();
    assert_eq!(
        fr_to_decimal(got),
        "18821383157269793795438455681495246036402687001665670618754263018637548127333",
        "Poseidon4 mismatch vs circomlib"
    );
}

#[test]
fn cross_client_commitment_matches_circomlib() {
    let commitment = poseidon3(DOMAIN_COMMITMENT, Fr::from(1u64), Fr::from(2u64)).unwrap();
    // circomlib: p([DOMAIN_COMMITMENT, 1n, 2n])
    assert_eq!(
        fr_to_decimal(commitment),
        "3073948565060944732767652572983061717417199761455075975621368839757913951698",
        "commitment mismatch vs circomlib"
    );
}

#[test]
fn cross_client_nullifier_hash_matches_circomlib() {
    let nh = poseidon4(
        DOMAIN_NULLIFIER,
        Fr::from(2u64),
        Fr::from(1u64),
        Fr::from(54321u64),
    )
    .unwrap();
    // circomlib: p([DOMAIN_NULLIFIER, 2n, 1n, 54321n])
    assert_eq!(
        fr_to_decimal(nh),
        "15673897871357144688463852956459858965792034609705466254389612987379294705967",
        "nullifier_hash mismatch vs circomlib"
    );
}

// ── Witness tests ────────────────────────────────────────────────────────────

#[test]
fn witness_build_and_root_consistency() {
    let secret = Fr::from(7u64);
    let nullifier = Fr::from(13u64);
    let (path_elements, path_indices) = zero_path();

    let w = WitnessInput::build(
        secret,
        nullifier,
        path_elements,
        path_indices,
        Fr::from(1u64),
        Fr::from(42u64),
        Fr::from(99u64),
    )
    .expect("witness build must succeed for zero path");

    // Re-compute root independently and compare.
    let commitment = poseidon3(DOMAIN_COMMITMENT, secret, nullifier).unwrap();
    let expected_root = compute_merkle_root(commitment, &path_elements, &path_indices).unwrap();
    assert_eq!(w.root, expected_root);
}

#[test]
fn witness_wrong_root_is_detected() {
    let (path_elements, path_indices) = zero_path();
    let w = WitnessInput::build(
        Fr::from(1u64),
        Fr::from(2u64),
        path_elements,
        path_indices,
        Fr::from(1u64),
        Fr::from(1u64),
        Fr::from(1u64),
    )
    .unwrap();

    let wrong_root = Fr::from(999u64);
    assert!(w.verify_root(wrong_root).is_err());
    assert!(w.verify_root(w.root).is_ok());
}

#[test]
fn nullifier_hash_differs_across_chains() {
    let (path_elements, path_indices) = zero_path();

    let w1 = WitnessInput::build(
        Fr::from(1u64),
        Fr::from(2u64),
        path_elements,
        path_indices,
        Fr::from(1u64), // chain_id = 1
        Fr::from(42u64),
        Fr::from(1u64),
    )
    .unwrap();

    let w2 = WitnessInput::build(
        Fr::from(1u64),
        Fr::from(2u64),
        path_elements,
        path_indices,
        Fr::from(10u64), // chain_id = 10
        Fr::from(42u64),
        Fr::from(1u64),
    )
    .unwrap();

    assert_ne!(
        w1.nullifier_hash, w2.nullifier_hash,
        "nullifier_hash must differ across chain IDs"
    );
    // Root is chain-independent (Merkle commitment is the same)
    assert_eq!(w1.root, w2.root);
}

#[test]
fn merkle_path_with_nonzero_siblings_changes_root() {
    let leaf = poseidon3(DOMAIN_COMMITMENT, Fr::from(1u64), Fr::from(2u64)).unwrap();
    let (zero_elements, indices) = zero_path();

    let mut nonzero_elements = zero_elements;
    nonzero_elements[0] = Fr::from(123u64);

    let root_zero = compute_merkle_root(leaf, &zero_elements, &indices).unwrap();
    let root_nonzero = compute_merkle_root(leaf, &nonzero_elements, &indices).unwrap();
    assert_ne!(root_zero, root_nonzero);
}

// ── Full proof-generation tests ──────────────────────────────────────────────
// Require: scripts/compile.sh completed, NODE_PATH / npx available.

#[test]
#[ignore = "slow — run with: cargo test full_proof -- --include-ignored"]
fn full_proof_generation_and_local_verify() {
    use poseidra_prover::{generate_proof, ProvingKey};
    use std::path::Path;

    let build_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("build/circuits");
    let vkey_path = build_dir.join("withdraw/withdraw_vkey.json");

    let key = ProvingKey::load(&build_dir).expect("load proving key");

    let (path_elements, path_indices) = zero_path();
    let proof = generate_proof(
        &key,
        Fr::from(1u64),
        Fr::from(2u64),
        path_elements,
        path_indices,
        Fr::from(1u64),
        Fr::from(54321u64),
        Fr::from(12345u64),
    )
    .expect("proof generation must succeed");

    assert!(proof.proving_ms > 0, "proving time must be recorded");
    println!("Proving time: {} ms", proof.proving_ms);

    let ok = poseidra_prover::prover::verify_locally(&vkey_path, &proof)
        .expect("verify call must succeed");
    assert!(ok, "proof must verify against local vkey");
}

#[test]
#[ignore = "slow — run with: cargo test invalid_witness -- --include-ignored"]
fn invalid_witness_proof_is_rejected() {
    use poseidra_prover::prover::{prove, verify_locally};
    use poseidra_prover::{ProvingKey, WitnessInput};
    use std::path::Path;

    let build_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("build/circuits");
    let vkey_path = build_dir.join("withdraw/withdraw_vkey.json");
    let key = ProvingKey::load(&build_dir).unwrap();

    let (path_elements, path_indices) = zero_path();

    // Build a valid witness, then tamper with the root.
    let mut w = WitnessInput::build(
        Fr::from(1u64),
        Fr::from(2u64),
        path_elements,
        path_indices,
        Fr::from(1u64),
        Fr::from(54321u64),
        Fr::from(12345u64),
    )
    .unwrap();

    // Tamper: claim a different root
    w.root = Fr::from(999u64);

    // Witness generation will fail or proof will not verify
    let result = prove(&key, &w);
    match result {
        Err(_) => { /* expected: witness generator rejects inconsistent inputs */ }
        Ok(proof) => {
            let ok = verify_locally(&vkey_path, &proof).unwrap();
            assert!(!ok, "tampered witness must not produce a valid proof");
        }
    }
}
