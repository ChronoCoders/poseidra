// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";

contract ComplianceRegistryTest is Test {
    ComplianceRegistry registry;
    address authority = address(0xA11CE);
    address other     = address(0xB0B);

    bytes32 constant C1 = bytes32(uint256(1));
    bytes32 constant C2 = bytes32(uint256(2));

    function setUp() public {
        registry = new ComplianceRegistry(authority);
    }

    // ── Constructor ────────��──────────────────────────────────────────────────

    function test_FlaggingAuthorityIsSet() public view {
        assertEq(registry.flaggingAuthority(), authority);
    }

    function test_RevertIf_ZeroAuthority() public {
        vm.expectRevert("ComplianceRegistry: zero authority");
        new ComplianceRegistry(address(0));
    }

    // ── Association set ───────���──────────────────────────────────────��────────

    function test_AddToAssociationSet() public {
        vm.prank(authority);
        registry.addToAssociationSet(C1);
        assertTrue(registry.isAssociated(C1));
    }

    function test_RevertIf_NonAuthorityAddsToAssociation() public {
        vm.prank(other);
        vm.expectRevert("ComplianceRegistry: not authority");
        registry.addToAssociationSet(C1);
    }

    function test_RemoveFromAssociationSet() public {
        vm.startPrank(authority);
        registry.addToAssociationSet(C1);
        registry.removeFromAssociationSet(C1);
        vm.stopPrank();
        assertFalse(registry.isAssociated(C1));
    }

    function test_RevertIf_AddZeroCommitmentToAssociation() public {
        vm.prank(authority);
        vm.expectRevert("ComplianceRegistry: zero commitment");
        registry.addToAssociationSet(bytes32(0));
    }

    function test_AssociationSetEmitsEvent() public {
        vm.prank(authority);
        vm.expectEmit(true, false, false, false);
        emit ComplianceRegistry.AddedToAssociationSet(C1);
        registry.addToAssociationSet(C1);
    }

    // ── Exclusion set ─────────────────────────────────────────────────────────

    function test_AddToExclusionSet() public {
        vm.prank(authority);
        registry.addToExclusionSet(C1);
        assertTrue(registry.isExcluded(C1));
        assertGt(registry.getFlaggingTimestamp(C1), 0);
    }

    function test_ExclusionRemovesFromAssociation() public {
        vm.startPrank(authority);
        registry.addToAssociationSet(C1);
        assertTrue(registry.isAssociated(C1));
        registry.addToExclusionSet(C1);
        vm.stopPrank();
        assertFalse(registry.isAssociated(C1));
        assertTrue(registry.isExcluded(C1));
    }

    function test_FlaggingTimestampIsRecorded() public {
        uint256 t = block.timestamp;
        vm.prank(authority);
        registry.addToExclusionSet(C1);
        assertEq(registry.getFlaggingTimestamp(C1), t);
    }

    function test_RevertIf_FlagAlreadyFlagged() public {
        vm.startPrank(authority);
        registry.addToExclusionSet(C1);
        vm.expectRevert("ComplianceRegistry: already flagged");
        registry.addToExclusionSet(C1);
        vm.stopPrank();
    }

    function test_RevertIf_NonAuthorityAddsToExclusion() public {
        vm.prank(other);
        vm.expectRevert("ComplianceRegistry: not authority");
        registry.addToExclusionSet(C1);
    }

    function test_RevertIf_AddZeroCommitmentToExclusion() public {
        vm.prank(authority);
        vm.expectRevert("ComplianceRegistry: zero commitment");
        registry.addToExclusionSet(bytes32(0));
    }

    function test_NotFlaggedByDefault() public view {
        assertFalse(registry.isExcluded(C1));
        assertEq(registry.getFlaggingTimestamp(C1), 0);
    }

    // ── Authority transfer ────────────────────────────────────────────────────

    function test_ProposeAndAcceptAuthority() public {
        vm.prank(authority);
        registry.proposeAuthority(other);
        assertEq(registry.pendingAuthority(), other);

        vm.prank(other);
        registry.acceptAuthority();
        assertEq(registry.flaggingAuthority(), other);
        assertEq(registry.pendingAuthority(), address(0));
    }

    function test_RevertIf_NonAuthorityProposes() public {
        vm.prank(other);
        vm.expectRevert("ComplianceRegistry: not authority");
        registry.proposeAuthority(other);
    }

    function test_RevertIf_NonPendingAccepts() public {
        vm.prank(authority);
        registry.proposeAuthority(other);

        vm.prank(address(0xDEAD));
        vm.expectRevert("ComplianceRegistry: not pending authority");
        registry.acceptAuthority();
    }

    function test_RevertIf_ProposeZeroAuthority() public {
        vm.prank(authority);
        vm.expectRevert("ComplianceRegistry: zero authority");
        registry.proposeAuthority(address(0));
    }

    function test_AuthorityTransferEmitsEvents() public {
        vm.prank(authority);
        vm.expectEmit(true, true, false, false);
        emit ComplianceRegistry.AuthorityTransferProposed(authority, other);
        registry.proposeAuthority(other);

        vm.prank(other);
        vm.expectEmit(true, true, false, false);
        emit ComplianceRegistry.AuthorityTransferred(authority, other);
        registry.acceptAuthority();
    }

    // ── Fuzz ──────────��──────────────────────��────────────────────────────────

    function testFuzz_OnlyAuthorityCanModifySets(address caller, bytes32 commitment) public {
        vm.assume(caller != authority);
        vm.assume(commitment != bytes32(0));

        vm.prank(caller);
        vm.expectRevert("ComplianceRegistry: not authority");
        registry.addToAssociationSet(commitment);

        vm.prank(caller);
        vm.expectRevert("ComplianceRegistry: not authority");
        registry.addToExclusionSet(commitment);
    }
}
