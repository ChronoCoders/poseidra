// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ComplianceRegistry
/// @notice On-chain association and exclusion sets for Poseidra compliance.
///
/// Association set A: commitments that are valid and clean.
/// Exclusion set E:   commitments that have been flagged / sanctioned.
///
/// The flagging authority is a governance parameter — never hardcoded.
/// Authority transfers require a two-step process (propose → accept) to
/// prevent accidental loss of control.
contract ComplianceRegistry {
    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Current flagging authority.
    address public flaggingAuthority;

    /// @notice Pending new authority (must call acceptAuthority() to confirm).
    address public pendingAuthority;

    /// @notice association set: commitment hash → is valid
    mapping(bytes32 => bool) public associationSet;

    /// @notice exclusion set: commitment hash → flagging timestamp (0 = not flagged)
    /// Storing the timestamp enables temporal validity checks in compliance proofs:
    /// a proof generated before flaggingTimestamp[c] is considered valid at time t.
    mapping(bytes32 => uint256) public flaggingTimestamp;

    // ── Events ────────────────────────────────────────────────────────────────

    event AddedToAssociationSet(bytes32 indexed commitment);
    event RemovedFromAssociationSet(bytes32 indexed commitment);
    event AddedToExclusionSet(bytes32 indexed commitment, uint256 timestamp);
    event AuthorityTransferProposed(address indexed current, address indexed proposed);
    event AuthorityTransferred(address indexed previous, address indexed next);

    // ── Constructor ───────────────────────────────────────────────────────────

    /// @param _flaggingAuthority Initial governance address.
    ///        Must not be zero — zero address would permanently lock the sets.
    constructor(address _flaggingAuthority) {
        require(_flaggingAuthority != address(0), "ComplianceRegistry: zero authority");
        flaggingAuthority = _flaggingAuthority;
        emit AuthorityTransferred(address(0), _flaggingAuthority);
    }

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyAuthority() {
        _onlyAuthority();
        _;
    }

    function _onlyAuthority() internal view {
        require(msg.sender == flaggingAuthority, "ComplianceRegistry: not authority");
    }

    // ── Association set ───────────────────────────────────────────────────────

    /// @notice Mark a commitment as valid and clean.
    function addToAssociationSet(bytes32 commitment) external onlyAuthority {
        require(commitment != bytes32(0), "ComplianceRegistry: zero commitment");
        associationSet[commitment] = true;
        emit AddedToAssociationSet(commitment);
    }

    /// @notice Remove a commitment from the association set (e.g. after flagging).
    function removeFromAssociationSet(bytes32 commitment) external onlyAuthority {
        associationSet[commitment] = false;
        emit RemovedFromAssociationSet(commitment);
    }

    /// @notice Return true if `commitment` is in the association set.
    function isAssociated(bytes32 commitment) external view returns (bool) {
        return associationSet[commitment];
    }

    // ── Exclusion set ─────────────────────────────────────────────────────────

    /// @notice Flag a commitment. Records the block timestamp for temporal validity.
    ///         Also removes from the association set if present.
    function addToExclusionSet(bytes32 commitment) external onlyAuthority {
        require(commitment != bytes32(0), "ComplianceRegistry: zero commitment");
        require(flaggingTimestamp[commitment] == 0, "ComplianceRegistry: already flagged");

        flaggingTimestamp[commitment] = block.timestamp;

        // Remove from association set if present
        if (associationSet[commitment]) {
            associationSet[commitment] = false;
            emit RemovedFromAssociationSet(commitment);
        }

        emit AddedToExclusionSet(commitment, block.timestamp);
    }

    /// @notice Return true if `commitment` is in the exclusion set.
    function isExcluded(bytes32 commitment) external view returns (bool) {
        return flaggingTimestamp[commitment] != 0;
    }

    /// @notice Return the timestamp at which `commitment` was flagged, or 0 if not flagged.
    ///         Used by compliance proofs for temporal validity enforcement.
    function getFlaggingTimestamp(bytes32 commitment) external view returns (uint256) {
        return flaggingTimestamp[commitment];
    }

    // ── Authority transfer ────────────────────────────────────────────────────

    /// @notice Propose a new flagging authority. Must be accepted by the new address.
    function proposeAuthority(address newAuthority) external onlyAuthority {
        require(newAuthority != address(0), "ComplianceRegistry: zero authority");
        pendingAuthority = newAuthority;
        emit AuthorityTransferProposed(flaggingAuthority, newAuthority);
    }

    /// @notice Accept the authority role. Must be called by the proposed address.
    function acceptAuthority() external {
        require(msg.sender == pendingAuthority, "ComplianceRegistry: not pending authority");
        address previous = flaggingAuthority;
        flaggingAuthority = pendingAuthority;
        pendingAuthority = address(0);
        emit AuthorityTransferred(previous, flaggingAuthority);
    }
}
