/// PLONK proof generation via snarkjs.
///
/// Architecture: the Rust prover owns witness computation and validation;
/// snarkjs (Node.js) handles PLONK + KZG proof generation using the
/// circuit artifacts produced by `scripts/compile.sh`.
///
/// This produces proofs verifiable by the Verifier.sol generated with:
///   snarkjs plonk export solidityverifier withdraw.zkey Verifier.sol
///
/// The snarkjs subprocess is spawned with a clean environment — no secrets
/// from the parent process environment are forwarded.
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;


use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use crate::errors::{ParameterError, ProofError};
use crate::witness::WitnessInput;

/// Serialised PLONK proof + public signals, ready for on-chain verification.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proof {
    /// Raw snarkjs proof JSON bytes.
    pub proof_json: Vec<u8>,
    /// Public signals JSON bytes (decimal strings, circuit order).
    pub public_json: Vec<u8>,
    /// Proof generation time in milliseconds. Logged on every proof.
    pub proving_ms: u64,
}

/// Loaded circuit artifacts. Hold this for the lifetime of the prover process.
pub struct ProvingKey {
    /// Path to the .zkey file produced by `scripts/compile.sh`.
    pub zkey_path: PathBuf,
    /// Path to withdraw.wasm (witness generator).
    pub wasm_path: PathBuf,
    /// Path to the witness generator JS wrapper.
    pub gen_witness_js: PathBuf,
    /// Path to the local snarkjs CLI (`circuits/node_modules/snarkjs/cli.js`).
    /// Using `node <cli.js>` avoids `npx` network fetches and `.cmd` shell issues on Windows.
    pub snarkjs_cli: PathBuf,
}

impl ProvingKey {
    /// Load proving key by pointing at a build directory produced by compile.sh.
    ///
    /// Expected layout:
    /// ```text
    /// build_dir/                           (e.g. build/circuits)
    ///   withdraw/
    ///     withdraw.zkey
    ///     withdraw_js/
    ///       withdraw.wasm
    ///       generate_witness.js
    /// <project_root>/
    ///   circuits/node_modules/snarkjs/cli.js
    /// ```
    pub fn load(build_dir: &Path) -> Result<Self, ParameterError> {
        let base = build_dir.join("withdraw");
        let zkey_path = base.join("withdraw.zkey");
        let wasm_path = base.join("withdraw_js").join("withdraw.wasm");
        let gen_witness_js = base.join("withdraw_js").join("generate_witness.js");

        // Derive project root: build_dir is <root>/build/circuits, so root = ../../
        let project_root = build_dir
            .parent()
            .and_then(|p| p.parent())
            .ok_or_else(|| ParameterError::Io {
                path: build_dir.display().to_string(),
                source: std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "cannot derive project root from build_dir",
                ),
            })?;
        let snarkjs_cli = project_root
            .join("circuits")
            .join("node_modules")
            .join("snarkjs")
            .join("cli.js");

        for (label, p) in [
            ("zkey", &zkey_path),
            ("wasm", &wasm_path),
            ("generate_witness.js", &gen_witness_js),
            ("snarkjs cli.js", &snarkjs_cli),
        ] {
            if !p.exists() {
                return Err(ParameterError::Io {
                    path: p.display().to_string(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::NotFound,
                        format!("circuit artifact '{label}' not found — run scripts/compile.sh"),
                    ),
                });
            }
        }

        debug!("loaded proving key from {}", base.display());
        Ok(Self {
            zkey_path,
            wasm_path,
            gen_witness_js,
            snarkjs_cli,
        })
    }
}

/// Generate a PLONK proof for the given witness.
///
/// # Timing
/// Prints actual proving time on every call (target: < 2 000 ms on desktop).
/// Proving time is also embedded in the returned `Proof`.
pub fn prove(key: &ProvingKey, witness: &WitnessInput) -> Result<Proof, ProofError> {
    let tmp = tempdir()?;

    let input_path = tmp.join("input.json");
    let wtns_path = tmp.join("witness.wtns");
    let proof_path = tmp.join("proof.json");
    let public_path = tmp.join("public.json");

    // 1. Write circom input JSON
    let input_json = witness.to_circom_json()?;
    std::fs::write(&input_path, &input_json)
        .map_err(|e| ProofError::Generation(format!("write input JSON: {e}")))?;

    // 2. Generate .wtns via circom's WASM witness generator
    let wtns_status = Command::new("node")
        .env_clear()
        .env("PATH", std::env::var("PATH").unwrap_or_default())
        .arg(&key.gen_witness_js)
        .arg(&key.wasm_path)
        .arg(&input_path)
        .arg(&wtns_path)
        .output()
        .map_err(|e| ProofError::Generation(format!("spawn witness generator: {e}")))?;

    if !wtns_status.status.success() {
        let stderr = String::from_utf8_lossy(&wtns_status.stderr);
        return Err(ProofError::Generation(format!(
            "witness generation failed: {stderr}"
        )));
    }

    // 3. Generate PLONK proof
    let t0 = Instant::now();

    let prove_status = Command::new("node")
        .env_clear()
        .env("PATH", std::env::var("PATH").unwrap_or_default())
        .arg(&key.snarkjs_cli)
        .args([
            "plonk",
            "prove",
            key.zkey_path.to_str().unwrap(),
            wtns_path.to_str().unwrap(),
            proof_path.to_str().unwrap(),
            public_path.to_str().unwrap(),
        ])
        .output()
        .map_err(|e| ProofError::Generation(format!("spawn snarkjs: {e}")))?;

    let proving_ms = t0.elapsed().as_millis() as u64;
    info!(proving_ms, "proof generated");

    if !prove_status.status.success() {
        let stderr = String::from_utf8_lossy(&prove_status.stderr);
        return Err(ProofError::Generation(format!(
            "snarkjs plonk prove failed: {stderr}"
        )));
    }

    let proof_json = std::fs::read(&proof_path)
        .map_err(|e| ProofError::Serialization(format!("read proof.json: {e}")))?;
    let public_json = std::fs::read(&public_path)
        .map_err(|e| ProofError::Serialization(format!("read public.json: {e}")))?;

    if proving_ms > 2_000 {
        tracing::warn!(
            proving_ms,
            "proving time exceeds 2 s target — investigate circuit or hardware"
        );
    }

    Ok(Proof {
        proof_json,
        public_json,
        proving_ms,
    })
}

/// Verify a proof against the verification key (for testing / CI).
/// Production verification happens on-chain via Verifier.sol.
pub fn verify_locally(
    snarkjs_cli: &Path,
    vkey_path: &Path,
    proof: &Proof,
) -> Result<bool, ProofError> {
    let tmp = tempdir()?;
    let proof_path = tmp.join("proof.json");
    let public_path = tmp.join("public.json");

    std::fs::write(&proof_path, &proof.proof_json)
        .map_err(|e| ProofError::Generation(format!("write proof: {e}")))?;
    std::fs::write(&public_path, &proof.public_json)
        .map_err(|e| ProofError::Generation(format!("write public: {e}")))?;

    let status = Command::new("node")
        .env_clear()
        .env("PATH", std::env::var("PATH").unwrap_or_default())
        .arg(snarkjs_cli)
        .args([
            "plonk",
            "verify",
            vkey_path.to_str().unwrap(),
            public_path.to_str().unwrap(),
            proof_path.to_str().unwrap(),
        ])
        .output()
        .map_err(|e| ProofError::Generation(format!("spawn snarkjs verify: {e}")))?;

    Ok(status.status.success())
}

fn tempdir() -> Result<PathBuf, ProofError> {
    let dir = std::env::temp_dir().join(format!(
        "poseidra_{:016x}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos())
            .unwrap_or(0)
    ));
    std::fs::create_dir_all(&dir)
        .map_err(|e| ProofError::Generation(format!("create temp dir: {e}")))?;
    Ok(dir)
}
