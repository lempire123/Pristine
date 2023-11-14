// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Pristine} from "../src/Pristine.sol";
import {Satoshi} from "../src/SatoshiERC20.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Pristine pristine = new Pristine();
        Satoshi satoshi = new Satoshi(address(pristine));

        vm.stopBroadcast();
    }
}
