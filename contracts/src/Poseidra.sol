// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleTree} from "./MerkleTree.sol";
import {IVerifier} from "./Verifier.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

/// @title Poseidra
/// @notice Non-custodial ZK privacy protocol.
///
/// Users deposit a fixed denomination and receive a secret note (secret, nullifier).
/// To withdraw, they prove knowledge of a note in the Merkle tree without revealing
/// which note — unlinking deposit from withdrawal.
///
/// Denomination is fixed at construction. Only one denomination per contract
/// instance, preventing cross-denomination correlation.
///
/// Nullifiers are scoped per chain + contract address (enforced in the circuit),
/// making replay across chains or contract versions impossible.
contract Poseidra is MerkleTree {
    // ── Constants ─────────────────────────────────────────────────────────────

    uint256 public immutable DENOMINATION;

    // ── State ─────────────────────────────────────────────────────────────────

    IVerifier public immutable VERIFIER;
    ComplianceRegistry public immutable COMPLIANCE_REGISTRY;

    /// @notice Nullifiers that have been spent. Prevents double-spend.
    mapping(bytes32 => bool) public nullifierSpent;

    // ── Events ────────────────────────────────────────────────────────────────

    event Deposit(
        bytes32 indexed commitment,
        uint256 leafIndex,
        uint256 timestamp
    );

    event Withdrawal(
        bytes32 indexed nullifierHash,
        address indexed recipient,
        address relayer,
        uint256 fee
    );

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _verifier          PLONK verifier (generated from withdraw.zkey).
    /// @param _complianceRegistry  ComplianceRegistry for association/exclusion checks.
    /// @param _denomination      Fixed deposit amount in wei.
    constructor(
        address _verifier,
        address _complianceRegistry,
        uint256 _denomination
    ) MerkleTree() {
        require(_verifier != address(0), "Poseidra: zero verifier");
        require(_complianceRegistry != address(0), "Poseidra: zero registry");
        require(_denomination > 0, "Poseidra: zero denomination");

        VERIFIER           = IVerifier(_verifier);
        COMPLIANCE_REGISTRY = ComplianceRegistry(_complianceRegistry);
        DENOMINATION       = _denomination;
    }

    // ── External ──────────────────────────────────────────────────────────────

    /// @notice Deposit exactly `DENOMINATION` wei and register a commitment.
    /// @param commitment Poseidon(DOMAIN_COMMITMENT, secret, nullifier).
    ///                   Must not already be in the tree.
    function deposit(bytes32 commitment) external payable {
        require(msg.value == DENOMINATION, "Poseidra: wrong denomination");
        require(uint256(commitment) < FIELD_SIZE, "Poseidra: commitment not in field");

        uint256 leafIndex = _insertLeaf(commitment);
        emit Deposit(commitment, leafIndex, block.timestamp);
    }

    /// @notice Withdraw using a ZK proof of Merkle inclusion.
    ///
    /// @param proof           PLONK proof encoded as 24 field elements (snarkjs format).
    /// @param root            Merkle root the proof was generated against.
    /// @param nullifierHash   Poseidon(DOMAIN_NULLIFIER, nullifier, chain_id, contract).
    /// @param recipient       Address to receive the withdrawn funds.
    /// @param relayer         Relayer address (receives `fee`). Zero for direct withdrawal.
    /// @param fee             Fee paid to the relayer, deducted from DENOMINATION.
    function withdraw(
        uint256[24] calldata proof,
        bytes32 root,
        bytes32 nullifierHash,
        address payable recipient,
        address payable relayer,
        uint256 fee
    ) external {
        require(isKnownRoot(root), "Poseidra: unknown or expired root");
        require(!nullifierSpent[nullifierHash], "Poseidra: note already spent");
        require(fee < DENOMINATION, "Poseidra: fee exceeds denomination");
        require(recipient != address(0), "Poseidra: zero recipient");

        // Public signals must match circuit's expected order:
        // [root, nullifier_hash, recipient, chain_id, contract_address]
        uint256[5] memory pubSignals = [
            uint256(root),
            uint256(nullifierHash),
            uint256(uint160(address(recipient))),
            block.chainid,
            uint256(uint160(address(this)))
        ];

        require(
            VERIFIER.verifyProof(proof, pubSignals),
            "Poseidra: invalid proof"
        );

        // Effects before interactions (CEI pattern)
        nullifierSpent[nullifierHash] = true;

        emit Withdrawal(nullifierHash, recipient, relayer, fee);

        // Interactions last
        uint256 amount = DENOMINATION - fee;
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "Poseidra: recipient transfer failed");

        if (fee > 0 && relayer != address(0)) {
            (bool feeOk,) = relayer.call{value: fee}("");
            require(feeOk, "Poseidra: relayer transfer failed");
        }
    }

    /// @notice Return true if a nullifier has been spent.
    function isSpent(bytes32 nullifierHash) external view returns (bool) {
        return nullifierSpent[nullifierHash];
    }

    /// @notice Return the current chain ID. Included in ZK proof public inputs.
    function chainId() external view returns (uint256) {
        return block.chainid;
    }
}
