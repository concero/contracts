// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DexSwap} from "contracts/DexSwap.sol";

contract DexSwapDeploy is Script {

    function run(address _proxy, address _owner) public returns(DexSwap dexSwap){
        vm.startBroadcast();
        dexSwap = new DexSwap(_proxy, _owner);
        vm.stopBroadcast();
    }
}
