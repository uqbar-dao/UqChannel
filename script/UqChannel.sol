// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console2 } from "forge-std/Script.sol";
import { UqChannel } from "../src/UqChannel.sol";
import { TestERC20 } from "../src/test/TestERC20.sol";

contract CounterScript is Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        UqChannel uqChannel = new UqChannel();
        TestERC20 testErc20 = new TestERC20();
    }
}
