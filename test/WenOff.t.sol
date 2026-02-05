// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WenOff} from "../src/WenOff.sol";

contract WenOffTest is Test {
    WenOff public wenOff;

    function setUp() public {
        wenOff = new WenOff();
    }

    // TODO: add tests
}
