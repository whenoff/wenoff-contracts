// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {WenOff} from "../src/WenOff.sol";

contract Deploy is Script {
    function run() external returns (WenOff wenOff) {
        vm.startBroadcast();
        wenOff = new WenOff();
        vm.stopBroadcast();
    }
}
