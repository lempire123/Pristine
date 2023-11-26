// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Pristine} from "../../src/Pristine.sol";
import {Satoshi} from "../../src/SatoshiERC20.sol";
import {IUniswapV2Router02} from "lib/amm/interfaces/IUniswapV2Router02.sol";
import {FlashloanReceiver} from "src/interfaces/IFlashloanReceiver.sol";

contract PristineTest is Test {
    using stdStorage for StdStorage;
    // Main contract - allows user to deposit Bitcoin and mint Satoshi
    Pristine public pristine;
    // Stablecoin being minted
    Satoshi public satoshi;
    // UniswapV2 router - we need this for liquidations.
    IUniswapV2Router02 public router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // This is the flashloan receiver contract.
    FlashloanReceiver public receiver;
    address public alice;
    address public bob;
    // Initial BTC balance for bob and alice.
    uint256 public constant INITIAL_BAL = 1000 * 10 ** 8;
    bytes public notOwnerError;
    address public WBTC = vm.envAddress("WBTC");
    address public ChainlinkOracle = vm.envAddress("CHAINLINK_WBTC_ORACLE");
    address public AaveOracle = vm.envAddress("AAVE_ORACLE");

    // The setup involved creating a fork of mainnet, deploying the contracts, and
    // funding alice and bob with some BTC (1000 BTC each)
    function setUp() public {
        vm.createSelectFork("https://api.securerpc.com/v1");
        pristine = new Pristine(WBTC, ChainlinkOracle, AaveOracle);
        satoshi = new Satoshi(address(pristine));
        pristine.initSatoshi(address(satoshi));
        alice = vm.addr(1);
        bob = vm.addr(2);
        deal(address(pristine.WBTC()), alice, INITIAL_BAL);
        deal(address(pristine.WBTC()), bob, INITIAL_BAL);
        notOwnerError = abi.encodeWithSelector(Pristine.NotOwner.selector);
    }
}
