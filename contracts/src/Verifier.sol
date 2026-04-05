// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Verifier.sol — PLONK/KZG on-chain verifier for the withdraw circuit.
//
// THIS FILE IS GENERATED. DO NOT EDIT MANUALLY.
//
// Generate with:
//   snarkjs plonk export solidityverifier build/circuits/withdraw/withdraw.zkey \
//       contracts/src/Verifier.sol
//
// Prerequisite: scripts/compile.sh must have completed successfully.
//
// The generated verifier accepts the same proof format produced by:
//   poseidra-prover::prover::prove()

// Placeholder interface — replaced by the snarkjs-generated contract.
// Poseidra.sol depends only on IVerifier; the implementation is swapped in
// once circuit compilation is complete.

interface IVerifier {
    /// @notice Verify a PLONK proof.
    /// @param proof    Serialised proof bytes.
    /// @param pubSignals Public signals in circuit order:
    ///                 [root, nullifier_hash, recipient, chain_id, contract_address]
    /// @return True iff the proof is valid.
    function verifyProof(
        bytes calldata proof,
        uint256[5] calldata pubSignals
    ) external view returns (bool);
}

// Stub implementation used for local Foundry tests before circuit compilation.
// Accepts all proofs so contract logic can be tested independently.
// MUST be replaced by the snarkjs-generated Verifier before deployment.
contract VerifierStub is IVerifier {
    // solhint-disable-next-line no-unused-vars
    function verifyProof(
        bytes calldata, /* proof */
        uint256[5] calldata /* pubSignals */
    ) external pure override returns (bool) {
        return true;
    }
}
