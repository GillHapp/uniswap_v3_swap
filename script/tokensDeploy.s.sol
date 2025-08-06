//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/script.sol";
import "../src/token0.sol";
import "../src/token1.sol";

contract tokensDeploy is Script {
    token0 public tokenA;
    token1 public tokenB;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        tokenA = new token0();
        tokenB = new token1();
        vm.stopBroadcast();
    }
}
