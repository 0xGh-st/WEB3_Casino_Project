// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Baccarat.sol";
import "../src/BaccaratProxy.sol";
contract DeployBaccaratAndProxy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        Baccarat baccarat = new Baccarat();

        bytes memory initializeData = abi.encodeWithSignature(
            "initialize(uint256,uint256,uint256)",
            0.1 ether,   // Minimum bet
            5 ether,     // Maximum bet
            5            // House edge percentage
        );

        BaccaratProxy proxy = new BaccaratProxy(
            address(baccarat),
            initializeData
        );

        vm.stopBroadcast();

        console.log("Baccarat Implementation deployed at:", address(baccarat));
        console.log("BaccaratProxy deployed at:", address(proxy));
    }
}

