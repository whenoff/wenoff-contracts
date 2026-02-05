// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WenOff} from "../src/WenOff.sol";

contract WenOffTest is Test {
    WenOff public wenOff;

    function setUp() public {
        wenOff = new WenOff(
            0.001 ether,  // lamp ONE
            0.001 ether,  // lamp TWO
            0.01 ether,   // lamp THREE
            address(1),
            address(2)
        );
    }

    // TODO: add tests
}
