// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Pristine} from "../../src/Pristine.sol";
import {Satoshi} from "../../src/SatoshiERC20.sol";
import {ISatoshi} from "src/interfaces/ISatoshiInterface.sol";
import {IUniswapV2Router02} from "lib/amm/interfaces/IUniswapV2Router02.sol";
import {FlashloanReceiver} from "src/interfaces/IFlashloanReceiver.sol";

contract SatoshiTest is Test {
    Pristine public pristine;
    Satoshi public satoshi;
    FlashloanReceiver public receiver;
    address public alice;
    address public bob;
    address public WBTC = vm.envAddress("WBTC");
    address public ChainlinkOracle = vm.envAddress("CHAINLINK_WBTC_ORACLE");
    address public AaveOracle = vm.envAddress("AAVE_ORACLE");

    function setUp() public {
        vm.createSelectFork("https://api.securerpc.com/v1");
        pristine = new Pristine(WBTC, ChainlinkOracle, AaveOracle);
        satoshi = new Satoshi(address(pristine));
        pristine.initSatoshi(address(satoshi));
        receiver = new FlashloanReceiver();
        alice = vm.addr(1);
        bob = vm.addr(2);
        deal(address(pristine.WBTC()), alice, 1000 * 10 ** 8);
        deal(address(pristine.WBTC()), bob, 1000 * 10 ** 8);
    }

    /*//////////////////////////////////////////////////////////////
                             TEST FLASHLOAN
    //////////////////////////////////////////////////////////////*/

    // function test_Flashloan() public {
    //     vm.startPrank(alice);
    //     receiver.flashloan(address(satoshi), 1000, new bytes[](0));
    // }
}
