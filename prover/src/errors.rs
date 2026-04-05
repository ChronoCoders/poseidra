use thiserror::Error;

#[derive(Debug, Error)]
pub enum WitnessError {
    #[error("commitment mismatch: computed {computed}, expected {expected}")]
    CommitmentMismatch { computed: String, expected: String },

    #[error("nullifier hash mismatch: computed {computed}, expected {expected}")]
    NullifierHashMismatch { computed: String, expected: String },

    #[error("Merkle path length {got} does not match tree depth {expected}")]
    MerklePathLength { got: usize, expected: usize },

    #[error("Merkle path verification failed: root {computed} does not match expected {expected}")]
    MerkleRootMismatch { computed: String, expected: String },

    #[error("path index out of range at level {level}: must be 0 or 1")]
    InvalidPathIndex { level: usize },

    #[error("Poseidon hash error: {0}")]
    Poseidon(String),
}

#[derive(Debug, Error)]
pub enum ProofError {
    #[error("proving key not loaded")]
    NoProvingKey,

    #[error("circuit synthesis failed: {0}")]
    Synthesis(String),

    #[error("proof generation failed: {0}")]
    Generation(String),

    #[error("proof serialization failed: {0}")]
    Serialization(String),

    #[error("witness error: {0}")]
    Witness(#[from] WitnessError),
}

#[derive(Debug, Error)]
pub enum ParameterError {
    #[error("failed to read params file at {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to deserialize params: {0}")]
    Deserialize(String),
}
