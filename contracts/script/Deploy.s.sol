// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VerifierStub} from "../src/Verifier.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {Poseidra} from "../src/Poseidra.sol";

/// @notice Deploy the full Poseidra protocol stack.
///
/// Required environment variables:
///   GOVERNANCE_ADDRESS   — address of the initial flagging authority
///   DENOMINATION         — fixed deposit amount in wei (e.g. 100000000000000000 = 0.1 ETH)
///   VERIFIER_ADDRESS     — address of the deployed Verifier contract
///                          (leave unset to deploy VerifierStub for local/testnet use only)
///
/// Usage:
///   # Local anvil
///   forge script contracts/script/Deploy.s.sol \
///       --rpc-url http://localhost:8545 \
///       --broadcast \
///       --private-key $DEPLOYER_KEY
///
///   # Testnet
///   forge script contracts/script/Deploy.s.sol \
///       --rpc-url $RPC_URL \
///       --broadcast \
///       --verify \
///       --etherscan-api-key $ETHERSCAN_KEY \
///       --private-key $DEPLOYER_KEY
///
/// Deployed addresses are written to deployments/{chainId}.json.
contract DeployPoseidra is Script {
    function run() external {
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        uint256 denomination = vm.envUint("DENOMINATION");

        // Verifier: use deployed address if provided, else stub (not for mainnet).
        address verifierAddr;
        try vm.envAddress("VERIFIER_ADDRESS") returns (address v) {
            verifierAddr = v;
        } catch {
            console.log("VERIFIER_ADDRESS not set - deploying VerifierStub (testnet/local only)");
            verifierAddr = address(0);
        }

        require(governance != address(0), "Deploy: GOVERNANCE_ADDRESS not set");
        require(denomination > 0, "Deploy: DENOMINATION not set");

        vm.startBroadcast();

        // 1. Compliance registry
        ComplianceRegistry registry = new ComplianceRegistry(governance);
        console.log("ComplianceRegistry:", address(registry));

        // 2. Verifier (stub if not provided)
        if (verifierAddr == address(0)) {
            VerifierStub stub = new VerifierStub();
            verifierAddr = address(stub);
            console.log("VerifierStub (NOT FOR MAINNET):", verifierAddr);
        } else {
            console.log("Verifier:", verifierAddr);
        }

        // 3. Core protocol
        Poseidra poseidra = new Poseidra(verifierAddr, address(registry), denomination);
        console.log("Poseidra:", address(poseidra));
        console.log("Denomination:", denomination);
        console.log("ChainId:", block.chainid);

        vm.stopBroadcast();

        // Write deployment record
        _writeDeployment(address(registry), verifierAddr, address(poseidra));
    }

    function _writeDeployment(
        address registry,
        address verifier,
        address poseidra
    ) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory json = string(abi.encodePacked(
            '{"chainId":', chainId,
            ',"ComplianceRegistry":"', vm.toString(registry),
            '","Verifier":"', vm.toString(verifier),
            '","Poseidra":"', vm.toString(poseidra),
            '"}'
        ));

        string memory path = string(abi.encodePacked(
            "deployments/", chainId, ".json"
        ));
        vm.writeFile(path, json);
        console.log("Deployment written to:", path);
    }
}
