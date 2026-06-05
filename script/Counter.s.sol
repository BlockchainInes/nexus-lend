// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/NexusLendingPool.sol";

contract DeployNexusLendingPool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address borrowToken = vm.envAddress("BORROW_TOKEN");

        vm.startBroadcast(deployerPrivateKey);
        NexusLendingPool pool = new NexusLendingPool(borrowToken);
        vm.stopBroadcast();

        console.log("NexusLendingPool deployed at:", address(pool));
    }
}