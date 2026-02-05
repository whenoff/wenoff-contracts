// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {WenOff} from "../src/WenOff.sol";

/// @notice Deploy WenOff to Base Sepolia (or Base mainnet when RPC is switched).
/// @dev PRIVATE_KEY is read from env as hex (0x...); deployer EOA is derived with vm.addr(privateKey).
contract Deploy is Script {
    function run() external returns (WenOff wenOff) {
        uint256 privateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(privateKey);

        uint256 feeOne = vm.envOr("FEE_ONE_WEI", uint256(0.001 ether));
        uint256 feeTwo = vm.envOr("FEE_TWO_WEI", uint256(0.001 ether));
        uint256 feeThree = vm.envOr("FEE_THREE_WEI", uint256(0.01 ether));
        address protocol = vm.envAddress("PROTOCOL_BENEFICIARY");
        address ecosystem = vm.envAddress("ECOSYSTEM_BENEFICIARY");

        vm.startBroadcast(privateKey);
        wenOff = new WenOff(feeOne, feeTwo, feeThree, protocol, ecosystem);
        vm.stopBroadcast();

        console.log("WenOff deployed");
        console.log("  deployer: ", deployer);
        console.log("  chainId:  ", block.chainid);
        console.log("  contract: ", address(wenOff));
    }
}

/*
  Verification on BaseScan (run after deployment, do not auto-verify in script):

  1. Get BaseScan API key from https://basescan.org/myapikey

  2. Verify on Base Sepolia:
     forge verify-contract <DEPLOYED_ADDRESS> src/WenOff.sol:WenOff \
       --chain-id 84532 \
       --etherscan-api-key $BASESCAN_API_KEY \
       --constructor-args $(cast abi-encode "constructor(uint256,uint256,uint256,address,address)" \
         "$FEE_ONE_WEI" "$FEE_TWO_WEI" "$FEE_THREE_WEI" "$PROTOCOL_BENEFICIARY" "$ECOSYSTEM_BENEFICIARY")

  3. Verify on Base mainnet (chain-id 8453):
     Same as above, replace --chain-id 8453 and use mainnet RPC/API.
*/
