// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {WenOff} from "../src/WenOff.sol";

contract Deploy is Script {
    function run() external returns (WenOff wenOff) {
        uint256 feeOne = vm.envOr("FEE_ONE_WEI", uint256(0.001 ether));
        uint256 feeTwo = vm.envOr("FEE_TWO_WEI", uint256(0.001 ether));
        uint256 feeThree = vm.envOr("FEE_THREE_WEI", uint256(0.01 ether));
        address protocol = vm.envAddress("PROTOCOL_BENEFICIARY");
        address ecosystem = vm.envAddress("ECOSYSTEM_BENEFICIARY");
        vm.startBroadcast();
        wenOff = new WenOff(feeOne, feeTwo, feeThree, protocol, ecosystem);
        vm.stopBroadcast();
    }
}
