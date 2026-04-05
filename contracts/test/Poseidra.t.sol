// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Poseidra} from "../src/Poseidra.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {VerifierStub, IVerifier} from "../src/Verifier.sol";

contract PoseidraTest is Test {
    Poseidra poseidra;
    ComplianceRegistry registry;
    VerifierStub verifier;

    address governance = address(0xDAD);
    address alice      = address(0xA11CE);
    address relayer    = address(0x4E1A7E4);

    uint256 constant DENOM = 0.1 ether;

    // Preset commitment values — must be valid BN254 field elements.
    // These are small integers for simplicity; valid since they're < FIELD_SIZE.
    bytes32 constant COMMITMENT_1 = bytes32(uint256(1));
    bytes32 constant COMMITMENT_2 = bytes32(uint256(2));

    // Pre-computed nullifier hash used across double-spend tests.
    // In production this comes from the circuit; here we use an arbitrary value.
    bytes32 constant NULLIFIER_HASH = bytes32(uint256(0xDEAD));

    function setUp() public {
        registry = new ComplianceRegistry(governance);
        verifier = new VerifierStub();
        poseidra = new Poseidra(address(verifier), address(registry), DENOM);
        vm.deal(alice, 10 ether);
        vm.deal(relayer, 1 ether);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_DenominationIsSet() public view {
        assertEq(poseidra.DENOMINATION(), DENOM);
    }

    function test_VerifierIsSet() public view {
        assertEq(address(poseidra.VERIFIER()), address(verifier));
    }

    function test_RevertIf_ZeroVerifier() public {
        vm.expectRevert("Poseidra: zero verifier");
        new Poseidra(address(0), address(registry), DENOM);
    }

    function test_RevertIf_ZeroRegistry() public {
        vm.expectRevert("Poseidra: zero registry");
        new Poseidra(address(verifier), address(0), DENOM);
    }

    function test_RevertIf_ZeroDenomination() public {
        vm.expectRevert("Poseidra: zero denomination");
        new Poseidra(address(verifier), address(registry), 0);
    }

    // ── Deposit ───────────────────────────────────────────────────────────────

    function test_Deposit() public {
        vm.prank(alice);
        poseidra.deposit{value: DENOM}(COMMITMENT_1);

        assertEq(poseidra.nextLeafIndex(), 1);
        assertEq(address(poseidra).balance, DENOM);
    }

    function test_DepositEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Poseidra.Deposit(COMMITMENT_1, 0, block.timestamp);
        poseidra.deposit{value: DENOM}(COMMITMENT_1);
    }

    function test_RevertIf_WrongDenomination() public {
        vm.prank(alice);
        vm.expectRevert("Poseidra: wrong denomination");
        poseidra.deposit{value: DENOM - 1}(COMMITMENT_1);
    }

    function test_RevertIf_CommitmentNotInField() public {
        bytes32 outOfField = bytes32(poseidra.FIELD_SIZE());
        vm.prank(alice);
        vm.expectRevert("Poseidra: commitment not in field");
        poseidra.deposit{value: DENOM}(outOfField);
    }

    function test_MultipleDeposits() public {
        vm.startPrank(alice);
        poseidra.deposit{value: DENOM}(COMMITMENT_1);
        poseidra.deposit{value: DENOM}(COMMITMENT_2);
        vm.stopPrank();

        assertEq(poseidra.nextLeafIndex(), 2);
        assertEq(address(poseidra).balance, 2 * DENOM);
    }

    // ── Withdraw ──────────────────────────────────────────────────────────────

    /// @dev Returns an all-zero PLONK proof array (valid for VerifierStub).
    function _emptyProof() internal pure returns (uint256[24] memory p) {}

    function _doDeposit() internal returns (bytes32 root) {
        vm.prank(alice);
        poseidra.deposit{value: DENOM}(COMMITMENT_1);
        root = poseidra.getLastRoot();
    }

    function test_Withdraw() public {
        bytes32 root = _doDeposit();
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        poseidra.withdraw(_emptyProof(),
            root,
            NULLIFIER_HASH,
            payable(alice),
            payable(address(0)),
            0
        );

        assertEq(alice.balance, aliceBefore + DENOM);
        assertTrue(poseidra.isSpent(NULLIFIER_HASH));
    }

    function test_WithdrawWithRelayerFee() public {
        bytes32 root = _doDeposit();
        uint256 fee = 0.01 ether;
        uint256 aliceBefore   = alice.balance;
        uint256 relayerBefore = relayer.balance;

        vm.prank(alice);
        poseidra.withdraw(_emptyProof(),
            root,
            NULLIFIER_HASH,
            payable(alice),
            payable(relayer),
            fee
        );

        assertEq(alice.balance,   aliceBefore   + DENOM - fee);
        assertEq(relayer.balance, relayerBefore + fee);
    }

    function test_WithdrawEmitsEvent() public {
        bytes32 root = _doDeposit();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Poseidra.Withdrawal(NULLIFIER_HASH, alice, address(0), 0);
        poseidra.withdraw(_emptyProof(),
            root,
            NULLIFIER_HASH,
            payable(alice),
            payable(address(0)),
            0
        );
    }

    function test_RevertIf_DoubleSpend() public {
        bytes32 root = _doDeposit();

        vm.startPrank(alice);
        poseidra.withdraw(_emptyProof(), root, NULLIFIER_HASH, payable(alice), payable(address(0)), 0);

        vm.expectRevert("Poseidra: note already spent");
        poseidra.withdraw(_emptyProof(), root, NULLIFIER_HASH, payable(alice), payable(address(0)), 0);
        vm.stopPrank();
    }

    function test_RevertIf_StaleRoot() public {
        // Capture the root right after the target deposit — this is the one we'll try to use.
        bytes32 depositRoot = _doDeposit();

        // Insert ROOT_HISTORY_SIZE more leaves to push depositRoot out of the 100-root window.
        // Needs exactly ROOT_HISTORY_SIZE insertions to evict it.
        vm.deal(alice, DENOM * (poseidra.ROOT_HISTORY_SIZE() + 1));
        for (uint256 i = 0; i < poseidra.ROOT_HISTORY_SIZE(); i++) {
            vm.prank(alice);
            poseidra.deposit{value: DENOM}(bytes32(i + 100));
        }

        // Confirm depositRoot is no longer in the window.
        assertFalse(poseidra.isKnownRoot(depositRoot));

        vm.prank(alice);
        vm.expectRevert("Poseidra: unknown or expired root");
        poseidra.withdraw(_emptyProof(), depositRoot, NULLIFIER_HASH, payable(alice), payable(address(0)), 0
        );
    }

    function test_RevertIf_FeeExceedsDenomination() public {
        bytes32 root = _doDeposit();

        vm.prank(alice);
        vm.expectRevert("Poseidra: fee exceeds denomination");
        poseidra.withdraw(_emptyProof(), root, NULLIFIER_HASH, payable(alice), payable(relayer), DENOM);
    }

    function test_RevertIf_ZeroRecipient() public {
        bytes32 root = _doDeposit();

        vm.prank(alice);
        vm.expectRevert("Poseidra: zero recipient");
        poseidra.withdraw(_emptyProof(), root, NULLIFIER_HASH, payable(address(0)), payable(address(0)), 0);
    }

    function test_IsSpent_ReturnsFalseBeforeWithdraw() public view {
        assertFalse(poseidra.isSpent(NULLIFIER_HASH));
    }

    // ── Poseidon cross-verification ───────────────────────────────────────────
    // Tests use PoseidonExposer (defined below) to call the assembly hasher.
    // Expected values verified against circomlibjs:
    //   buildPoseidon().then(p => console.log(p.F.toString(p([1n,2n]))))
    //   → 7853200120776062878684798364095072458815029376092732009249414926327459813530

    PoseidonExposer poseidonExposer;

    function _setUpExposer() internal {
        if (address(poseidonExposer) == address(0)) {
            poseidonExposer = new PoseidonExposer(address(verifier), address(registry), DENOM);
        }
    }

    function test_PoseidonVectors_SelfConsistency() public {
        _setUpExposer();
        uint256 h1 = poseidonExposer.poseidon2(1, 2);
        uint256 h2 = poseidonExposer.poseidon2(1, 2);
        assertEq(h1, h2);
    }

    function test_PoseidonVectors_OrderMatters() public {
        _setUpExposer();
        uint256 h1 = poseidonExposer.poseidon2(1, 2);
        uint256 h2 = poseidonExposer.poseidon2(2, 1);
        assertTrue(h1 != h2);
    }

    function test_PoseidonVectors_OutputInField() public {
        _setUpExposer();
        uint256 P = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
        uint256 h = poseidonExposer.poseidon2(1, 2);
        assertLt(h, P);
    }

    /// @dev Cross-client vector: circomlibjs Poseidon([1, 2]) output confirmed.
    function test_PoseidonVectors_CrossClient() public {
        _setUpExposer();
        uint256 h = poseidonExposer.poseidon2(1, 2);
        assertEq(h, 7853200120776062878684798364095072458815029376092732009249414926327459813530);
    }

    // ── Fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_DepositAndWithdraw(uint96 denomination) public {
        vm.assume(denomination > 0);

        Poseidra local = new Poseidra(address(verifier), address(registry), denomination);
        address user = address(0x1234);
        vm.deal(user, denomination);

        vm.prank(user);
        local.deposit{value: denomination}(COMMITMENT_1);

        bytes32 root = local.getLastRoot();
        bytes32 nullifier = bytes32(uint256(0xFEED));

        uint256 balBefore = user.balance;
        vm.prank(user);
        local.withdraw(_emptyProof(), root, nullifier, payable(user), payable(address(0)), 0);

        assertEq(user.balance, balBefore + denomination);
        assertTrue(local.isSpent(nullifier));
    }

    function testFuzz_InvalidProofIsRejected(uint256[24] calldata badProof) public {
        // Deploy with a real-but-rejecting verifier
        RejectingVerifier rejectVerifier = new RejectingVerifier();
        Poseidra local = new Poseidra(address(rejectVerifier), address(registry), DENOM);

        vm.deal(alice, DENOM);
        vm.prank(alice);
        local.deposit{value: DENOM}(COMMITMENT_1);
        bytes32 root = local.getLastRoot();

        vm.prank(alice);
        vm.expectRevert("Poseidra: invalid proof");
        local.withdraw(badProof, root, NULLIFIER_HASH, payable(alice), payable(address(0)), 0);
    }
}

/// @dev Verifier that always rejects — used for invalid proof fuzz tests.
contract RejectingVerifier is IVerifier {
    function verifyProof(uint256[24] calldata, uint256[5] calldata) external pure returns (bool) {
        return false;
    }
}

/// @dev Exposes _poseidon2 for cross-client vector tests.
contract PoseidonExposer is Poseidra {
    constructor(address v, address r, uint256 d) Poseidra(v, r, d) {}

    function poseidon2(uint256 a, uint256 b) external view returns (uint256) {
        return _poseidon2(a, b);
    }
}
