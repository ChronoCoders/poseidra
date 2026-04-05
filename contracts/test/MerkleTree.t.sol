// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MerkleTree} from "../src/MerkleTree.sol";

/// @dev Exposes internal MerkleTree functions for testing
contract MerkleTreeHarness is MerkleTree {
    function insertLeaf(bytes32 commitment) external returns (uint256) {
        return _insertLeaf(commitment);
    }
}

contract MerkleTreeTest is Test {
    MerkleTreeHarness tree;

    function setUp() public {
        tree = new MerkleTreeHarness();
    }

    // ── Construction ────────────────────────────��─────────────────────────────

    function test_InitialRootIsNonZero() public view {
        assertTrue(tree.getLastRoot() != bytes32(0));
    }

    function test_InitialLeafIndexIsZero() public view {
        assertEq(tree.nextLeafIndex(), 0);
    }

    // ── Insertion ─────────────────────────────────────────────────────────────

    function test_InsertSingleLeaf() public {
        bytes32 commitment = bytes32(uint256(1));
        uint256 idx = tree.insertLeaf(commitment);
        assertEq(idx, 0);
        assertEq(tree.nextLeafIndex(), 1);
    }

    function test_InsertChangesRoot() public {
        bytes32 root0 = tree.getLastRoot();
        tree.insertLeaf(bytes32(uint256(1)));
        bytes32 root1 = tree.getLastRoot();
        assertTrue(root0 != root1);
    }

    function test_DifferentCommitmentsProduceDifferentRoots() public {
        tree.insertLeaf(bytes32(uint256(1)));
        bytes32 root1 = tree.getLastRoot();

        MerkleTreeHarness tree2 = new MerkleTreeHarness();
        tree2.insertLeaf(bytes32(uint256(2)));
        bytes32 root2 = tree2.getLastRoot();

        assertTrue(root1 != root2);
    }

    function test_InsertEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit MerkleTree.LeafInserted(bytes32(uint256(42)), 0, block.timestamp);
        tree.insertLeaf(bytes32(uint256(42)));
    }

    function test_LeafIndexIncrements() public {
        for (uint256 i = 0; i < 5; i++) {
            uint256 idx = tree.insertLeaf(bytes32(i + 1));
            assertEq(idx, i);
        }
    }

    // ── Root history ──────────────────────────────────────────────────���───────

    function test_IsKnownRoot_CurrentRoot() public view {
        assertTrue(tree.isKnownRoot(tree.getLastRoot()));
    }

    function test_IsKnownRoot_PreviousRoot() public {
        tree.insertLeaf(bytes32(uint256(1)));
        bytes32 root0 = tree.roots(0);

        // root0 is in history (index 0 of ring buffer)
        assertTrue(tree.isKnownRoot(root0));
    }

    function test_IsKnownRoot_FalseForUnknown() public view {
        assertFalse(tree.isKnownRoot(bytes32(uint256(999))));
    }

    function test_IsKnownRoot_FalseForZero() public view {
        assertFalse(tree.isKnownRoot(bytes32(0)));
    }

    function test_RootHistoryWindowBoundary() public {
        // Insert ROOT_HISTORY_SIZE + 1 leaves; the oldest root should be evicted.
        bytes32 rootBefore = tree.getLastRoot();

        for (uint256 i = 0; i < tree.ROOT_HISTORY_SIZE() + 1; i++) {
            tree.insertLeaf(bytes32(i + 1));
        }

        // The root before any insertions is now outside the window
        assertFalse(tree.isKnownRoot(rootBefore));
    }

    function test_RootHistoryWindow_100thRootStillKnown() public {
        // Insert ROOT_HISTORY_SIZE leaves; the first inserted root should still be known.
        tree.insertLeaf(bytes32(uint256(1)));
        bytes32 firstInsertedRoot = tree.getLastRoot();

        for (uint256 i = 1; i < tree.ROOT_HISTORY_SIZE(); i++) {
            tree.insertLeaf(bytes32(i + 1));
        }

        assertTrue(tree.isKnownRoot(firstInsertedRoot));
    }

    // ── Fuzz ──────────────────────────────────────────────────────────────────

    /// @dev Any valid field element can be inserted and the root always changes.
    function testFuzz_InsertAnyLeaf(bytes32 commitment) public {
        vm.assume(uint256(commitment) > 0);
        vm.assume(uint256(commitment) < tree.FIELD_SIZE());

        bytes32 rootBefore = tree.getLastRoot();
        tree.insertLeaf(commitment);
        assertTrue(tree.getLastRoot() != rootBefore);
        assertTrue(tree.isKnownRoot(tree.getLastRoot()));
    }
}
