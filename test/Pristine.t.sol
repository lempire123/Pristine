// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Pristine.sol";
import "../src/SatoshiERC20.sol";
import {IUniswapV2Router02} from "lib/amm/interfaces/IUniswapV2Router02.sol";
import {FlashloanReceiver} from "src/interfaces/IFlashloanReceiver.sol";

contract PristineTest is Test {
    using stdStorage for StdStorage;
    Pristine public pristine;
    Satoshi public satoshi;
    IUniswapV2Router02 public router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    FlashloanReceiver public receiver;
    address public alice;
    address public bob;
    uint256 public constant INITIAL_BAL = 1000 * 10 ** 8;

    function setUp() public {
        vm.createSelectFork("https://api.securerpc.com/v1");
        pristine = new Pristine();
        satoshi = new Satoshi(address(pristine));
        pristine.initSatoshi(address(satoshi));
        alice = vm.addr(1);
        bob = vm.addr(2);
        deal(address(pristine.wBTC()), alice, INITIAL_BAL);
        deal(address(pristine.wBTC()), bob, INITIAL_BAL);
    }

    /*//////////////////////////////////////////////////////////////
                             CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_OpenPosition() public {
        vm.startPrank(alice);
        uint256 depositAmount = 1000 * 10 ** 8;
        pristine.wBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .getPosition(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == depositAmount);
        assert(debt == 0);
    }

    function test_Borrow() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(1000 * 10 ** 18, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .getPosition(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 10 * 10 ** 8);
        assert(debt == 1000 * 10 ** 18);
    }

    function test_Deposit() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        pristine.deposit(10 * 10 ** 8, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .getPosition(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 20 * 10 ** 8);
        assert(debt == 0);
    }

    function test_Withdraw() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        pristine.deposit(10 * 10 ** 8, id);
        pristine.withdraw(5 * 10 ** 8, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .getPosition(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 15 * 10 ** 8);
        assert(debt == 0);
    }

    function test_Repay() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(1000 * 10 ** 18, id);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        pristine.repay(1000 * 10 ** 18, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .getPosition(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 10 * 10 ** 8);
        assert(debt == 0);
    }

    function test_OpenMultiplePositionsSameOwner() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id1 = pristine.open(10 * 10 ** 8);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id2 = pristine.open(10 * 10 ** 8);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id3 = pristine.open(10 * 10 ** 8);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id4 = pristine.open(10 * 10 ** 8);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id5 = pristine.open(10 * 10 ** 8);
        assert(pristine.positionCounter() == 5);
        assert(id1 == 1);
        assert(id2 == 2);
        assert(id3 == 3);
        assert(id4 == 4);
        assert(id5 == 5);
    }

    function test_Limit(uint256 depositAmount, uint256 borrowAmount) public {
        vm.assume(depositAmount < 1000 && depositAmount > 0);
        vm.assume(borrowAmount < type(uint256).max / 10 ** 18);
        if (depositAmount * pristine.getCollatPrice() > borrowAmount) {
            vm.startPrank(alice);
            pristine.wBTC().approve(address(pristine), depositAmount * 10 ** 8);
            uint256 id = pristine.open(depositAmount * 10 ** 8);
            pristine.borrow(borrowAmount * 10 ** 18, id);
        } else {
            vm.startPrank(alice);
            pristine.wBTC().approve(address(pristine), depositAmount * 10 ** 8);
            uint256 id = pristine.open(depositAmount * 10 ** 8);
            bytes4 selector = Pristine.PositionNotHealthy.selector;
            bytes memory encodedError = abi.encodeWithSelector(selector, id);

            vm.expectRevert(encodedError);
            pristine.borrow(borrowAmount * 10 ** 18, id);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               FAIL CASES
    //////////////////////////////////////////////////////////////*/

    function test_BorrowTooMuch() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        bytes4 selector = Pristine.PositionNotHealthy.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector, id);

        vm.expectRevert(encodedError);
        pristine.borrow(26_000 * 10 ** 18, id);
    }

    function test_WithdrawTooMuch() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.expectRevert();
        pristine.withdraw(26_000 * 10 ** 8, id);
    }

    // Open question whether other should be able to deposit into your position
    function test_depositIntoOtherPosition() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.startPrank(bob);
        pristine.wBTC().approve(address(pristine), 1 * 10 ** 8);
        pristine.deposit(1 * 10 ** 8, id);
    }

    function test_borrowFromOtherPosition() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.startPrank(bob);
        vm.expectRevert("ONLY_OWNER");
        pristine.borrow(1, id);
    }

    function test_withdrawFromOtherPosition() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.startPrank(bob);
        vm.expectRevert("ONLY_OWNER");
        pristine.withdraw(1 * 10 ** 8, id);
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDATION
    //////////////////////////////////////////////////////////////*/

    function test_liquidateFailed() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(1000 * 10 ** 18, id);

        vm.startPrank(bob);
        satoshi.approve(address(pristine), type(uint256).max);
        deal(address(satoshi), bob, 1000 * 10 ** 18);
        vm.expectRevert("POSITION_HEALTHY");
        pristine.liquidatePosition(1);
    }

    function test_liquidateSuccess() public {
        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(40_000 * 10 ** 18, id);

        // Make position unhealthy
        // Collat Amount is third item in struct (index 2)
        // Could also increase borrow amount (index 3)
        stdstore
            .target(address(pristine))
            .sig("Positions(uint256)")
            .with_key(1)
            .depth(2)
            .checked_write(1 * 10 ** 8); // Position in struct to change

        assert(!pristine.checkPositionHealth(id));

        vm.startPrank(bob);
        uint256 btcBalanceBefore = pristine.wBTC().balanceOf(address(bob));
        satoshi.approve(address(pristine), type(uint256).max);
        deal(address(satoshi), bob, 40_000 * 10 ** 18);
        pristine.liquidatePosition(1);
        uint256 btcBalanceAfter = pristine.wBTC().balanceOf(address(bob));
        uint256 satoshiBalanceAfter = satoshi.balanceOf(address(bob));

        // Will be 1 BTC because we changed the storage to 1
        assert(btcBalanceAfter - btcBalanceBefore == 1 * 10 ** 8);
        assert(satoshiBalanceAfter == 0);

        vm.startPrank(alice);
        // Hey at least alice still has 40k, not bad
        assert(satoshi.balanceOf(address(alice)) == 40_000 * 10 ** 18);
        // Now alice tries to withdraw collat - fail
        vm.expectRevert("POSITION_NOT_FOUND");
        pristine.repay(40_000 * 10 ** 18, id);
    }

    // For this test we need to deploy a flashloan receiver contract
    // The receiver will flashloan the required amount to liquidate alice's position
    // It then will receive the btc, which it has to sell for satoshi to repay the loan
    // In order to sell, we need to deploy a uniV2 pool and seed it with liquidity
    function test_liquidateSuccessUsingFlashloan() public {
        deal(address(pristine.wBTC()), address(this), 1000 * 10 ** 8);
        deal(address(satoshi), address(this), 26_750_000 * 10 ** 18);
        pristine.wBTC().approve(address(router), 1000 * 10 ** 8);
        satoshi.approve(address(router), 26_750_000 * 10 ** 18);
        router.addLiquidity(
            address(satoshi),
            address(pristine.wBTC()),
            26_750_000 * 10 ** 18,
            1000 * 10 ** 8,
            0,
            0,
            address(this),
            block.timestamp + 1
        );
        receiver = new FlashloanReceiver();

        vm.startPrank(alice);
        pristine.wBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(50_000 * 10 ** 18, id);
        vm.stopPrank();

        // Make position unhealthy
        // Collat Amount is third item in struct (index 2)
        // Could also increase borrow amount (index 3)
        stdstore
            .target(address(pristine))
            .sig("Positions(uint256)")
            .with_key(1)
            .depth(2)
            .checked_write(2 * 10 ** 8); // Position in struct to change

        // 26700 x 2 = 53400
        assert(!pristine.checkPositionHealth(id));

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encode(id);
        data[1] = abi.encode(address(pristine));
        data[2] = abi.encode(address(router));
        receiver.flashloan(address(satoshi), 50_000 * 10 ** 18, data);
        receiver.withdraw(address(satoshi));
        assert(satoshi.balanceOf(address(this)) > 2000 * 10 ** 18);
        emit log_named_uint(
            "liquidation profit",
            satoshi.balanceOf(address(this)) / 10 ** 18
        );
    }
}
