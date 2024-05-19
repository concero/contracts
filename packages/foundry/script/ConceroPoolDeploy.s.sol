// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ConceroPool} from "../src/ConceroPool.sol";

contract ConceroPoolDeploy is Script {

    function run(address _link,address _ccipRouter) public returns(ConceroPool pool){
        vm.startBroadcast();
        pool = new ConceroPool(_link, _ccipRouter);
        vm.stopBroadcast();
    }
}
