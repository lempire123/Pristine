// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Pristine} from "../src/Pristine.sol";
import {Satoshi} from "../src/SatoshiERC20.sol";
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

    // The setup involved creating a fork of mainnet, deploying the contracts, and
    // funding alice and bob with some BTC (1000 BTC each)
    function setUp() public {
        vm.createSelectFork("https://api.securerpc.com/v1");
        pristine = new Pristine();
        satoshi = new Satoshi(address(pristine));
        pristine.initSatoshi(address(satoshi));
        alice = vm.addr(1);
        bob = vm.addr(2);
        deal(address(pristine.WBTC()), alice, INITIAL_BAL);
        deal(address(pristine.WBTC()), bob, INITIAL_BAL);
        notOwnerError = abi.encodeWithSelector(Pristine.NotOwner.selector);
    }

    /*//////////////////////////////////////////////////////////////
                             CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Tests opening a position
    function test_OpenPosition() public {
        vm.startPrank(alice);
        // Deposit 1000 BTC
        uint256 depositAmount = 1000 * 10 ** 8;
        pristine.WBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .Positions(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == depositAmount);
        assert(debt == 0);
        vm.stopPrank();
    }

    function test_Borrow() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(1000 * 10 ** 18, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .Positions(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 10 * 10 ** 8);
        assert(debt == 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function test_Deposit() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        pristine.deposit(10 * 10 ** 8, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .Positions(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 20 * 10 ** 8);
        assert(debt == 0);
        vm.stopPrank();
    }

    function test_Withdraw() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        pristine.deposit(10 * 10 ** 8, id);
        pristine.withdraw(5 * 10 ** 8, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .Positions(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 15 * 10 ** 8);
        assert(debt == 0);
        vm.stopPrank();
    }

    function test_Repay() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(1000 * 10 ** 18, id);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        pristine.repay(1000 * 10 ** 18, id);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .Positions(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == 10 * 10 ** 8);
        assert(debt == 0);
        vm.stopPrank();
    }

    function test_Limit(uint256 depositAmount, uint256 borrowAmount) public {
        vm.assume(depositAmount < 1000 && depositAmount > 0);
        vm.assume(
            borrowAmount < type(uint256).max / 10 ** 18 && borrowAmount > 0
        );
        if (
            (depositAmount * pristine.getCollatPrice() * 100) / borrowAmount >=
            110
        ) {
            vm.startPrank(alice);
            pristine.WBTC().approve(address(pristine), depositAmount * 10 ** 8);
            uint256 id = pristine.open(depositAmount * 10 ** 8);
            pristine.borrow(borrowAmount * 10 ** 18, id);
        } else {
            vm.startPrank(alice);
            pristine.WBTC().approve(address(pristine), depositAmount * 10 ** 8);
            uint256 id = pristine.open(depositAmount * 10 ** 8);
            bytes4 selector = Pristine.PositionNotHealthy.selector;
            bytes memory encodedError = abi.encodeWithSelector(selector, id);

            vm.expectRevert(encodedError);
            pristine.borrow(borrowAmount * 10 ** 18, id);
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RedeemRiskyPosition() public {
        uint256 btcPrice = pristine.getCollatPrice();
        uint256 depositAmount = 120 * 10 ** 8; // 10 btc
        uint256 borrowAmount = (100 * btcPrice * 10 ** 18); // 120% collat ratio
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        pristine.borrow(borrowAmount, id); // Calculated to make CR ~ 116.67%
        vm.stopPrank();

        uint256 redemptionRate = pristine.getRedemptionRate(id);

        vm.startPrank(bob);
        deal(address(pristine.Satoshi()), bob, 500 * 10 ** 18);
        pristine.redeem(id, 500 * 10 ** 18);
        uint256 satoshiAmountInBTC = (500 * 10 ** 18 * redemptionRate) /
            (btcPrice * 10 ** 12);
        vm.stopPrank();

        (, , uint256 collat, uint256 debt) = pristine.Positions(id);
        assert(collat == depositAmount - satoshiAmountInBTC);
        assert(debt == borrowAmount - (500 * 10 ** 18));
    }

    function test_RedeemMediumPosition() public {
        uint256 btcPrice = pristine.getCollatPrice();
        uint256 depositAmount = 160 * 10 ** 8; // 10 btc
        uint256 borrowAmount = (100 * btcPrice * 10 ** 18); // 160% collat ratio

        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        pristine.borrow(borrowAmount, id); // Calculated to make CR ~ 150%
        vm.stopPrank();

        uint256 redemptionRate = pristine.getRedemptionRate(id);

        vm.startPrank(bob);
        deal(address(pristine.Satoshi()), bob, 500 * 10 ** 18);
        pristine.redeem(id, 500 * 10 ** 18);
        uint256 satoshiAmountInBTC = (500 * 10 ** 18 * redemptionRate) /
            (btcPrice * 10 ** 12);
        vm.stopPrank();

        (, , uint256 collat, uint256 debt) = pristine.Positions(id);
        assert(collat == depositAmount - satoshiAmountInBTC);
        assert(debt == borrowAmount - (500 * 10 ** 18));
    }

    function test_RedeemSafePosition() public {
        uint256 btcPrice = pristine.getCollatPrice();
        uint256 depositAmount = 220 * 10 ** 8; // 10 btc
        uint256 borrowAmount = (100 * btcPrice * 10 ** 18); // 220% collat ratio

        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        pristine.borrow(borrowAmount, id); // Calculated to make CR ~ 300%
        vm.stopPrank();

        uint256 redemptionRate = pristine.getRedemptionRate(id);

        vm.startPrank(bob);
        deal(address(pristine.Satoshi()), bob, 500 * 10 ** 18);
        pristine.redeem(id, 500 * 10 ** 18);
        uint256 satoshiAmountInBTC = (500 * 10 ** 18 * redemptionRate) /
            (btcPrice * 10 ** 12);
        vm.stopPrank();

        (, , uint256 collat, uint256 debt) = pristine.Positions(id);
        assert(collat == depositAmount - satoshiAmountInBTC);
        assert(debt == borrowAmount - (500 * 10 ** 18));
    }

    function test_RedeemExcessAmount() public {
        uint256 btcPrice = pristine.getCollatPrice();
        uint256 depositAmount = 10 * 10 ** 8;
        uint256 COLLAT_RATIO = pristine.MIN_COLLAT_RATIO();
        uint256 borrowAmount = (depositAmount * btcPrice * 10 ** 10) /
            (COLLAT_RATIO * 10 ** 2);
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        pristine.borrow(borrowAmount, id);
        vm.stopPrank();

        vm.startPrank(bob);
        deal(address(pristine.Satoshi()), bob, 500 * 10 ** 18);
        bytes4 selector = Pristine.NotEnoughDebt.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector);

        vm.expectRevert(encodedError);
        pristine.redeem(id, 500 * 10 ** 18);
        vm.stopPrank();
    }

    function test_RedeemWithoutBorrow() public {
        uint256 depositAmount = 10 * 10 ** 8;
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), depositAmount);
        uint256 id = pristine.open(depositAmount);
        // No borrow
        vm.stopPrank();

        vm.startPrank(bob);
        deal(address(pristine.Satoshi()), bob, 500 * 10 ** 18);
        bytes4 selector = Pristine.NotEnoughDebt.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector);

        vm.expectRevert(encodedError);
        pristine.redeem(id, 500 * 10 ** 18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               FAIL CASES
    //////////////////////////////////////////////////////////////*/

    // Protocol does not allow same address to open multiple positions
    // Not sure if this is the best design?!
    function test_TryOpenPositionTwice() public {
        vm.startPrank(alice);
        // Deposit 1000 BTC
        uint256 depositAmount = 500 * 10 ** 8;
        pristine.WBTC().approve(address(pristine), depositAmount * 2);
        uint256 id = pristine.open(depositAmount);
        (address owner, uint256 _id, uint256 collat, uint256 debt) = pristine
            .Positions(id);
        assert(owner == alice);
        assert(_id == 1);
        assert(collat == depositAmount);
        assert(debt == 0);
        bytes4 selector = Pristine.CannotCreateMultiplePositions.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector);

        vm.expectRevert(encodedError);
        id = pristine.open(depositAmount);
        vm.stopPrank();
    }

    function test_BorrowTooMuch() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        bytes4 selector = Pristine.PositionNotHealthy.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector, id);

        uint256 btcPrice = pristine.getCollatPrice();
        vm.expectRevert(encodedError);
        pristine.borrow(btcPrice * 10 ** 18, id);
        vm.stopPrank();
    }

    function test_WithdrawTooMuch() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.expectRevert();
        pristine.withdraw(26_000 * 10 ** 8, id);
        vm.stopPrank();
    }

    // Open question whether other should be able to deposit into your position
    // Protocol currently allows it
    function test_depositIntoOtherPosition() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.startPrank(bob);
        pristine.WBTC().approve(address(pristine), 1 * 10 ** 8);
        pristine.deposit(1 * 10 ** 8, id);
        vm.stopPrank();
    }

    function test_borrowFromOtherPosition() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.startPrank(bob);
        vm.expectRevert(notOwnerError);
        pristine.borrow(1, id);
        vm.stopPrank();
    }

    function test_withdrawFromOtherPosition() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 1 * 10 ** 8);
        uint256 id = pristine.open(1 * 10 ** 8);

        vm.startPrank(bob);
        vm.expectRevert(notOwnerError);
        pristine.withdraw(1 * 10 ** 8, id);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDATION
    //////////////////////////////////////////////////////////////*/

    function test_liquidateFailed() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
        uint256 id = pristine.open(10 * 10 ** 8);
        pristine.borrow(1000 * 10 ** 18, id);

        vm.startPrank(bob);
        satoshi.approve(address(pristine), type(uint256).max);
        deal(address(satoshi), bob, 1000 * 10 ** 18);
        bytes4 selector = Pristine.PositionHealthy.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector, id);

        vm.expectRevert(encodedError);
        pristine.liquidatePosition(1);
        vm.stopPrank();
    }

    // This liquidation is probably unprofitable.
    // Unlike using a flashloan where a profit is required to repay the loan.
    // (Or at least break even)
    function test_liquidateSuccess() public {
        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 10 * 10 ** 8);
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
        uint256 btcBalanceBefore = pristine.WBTC().balanceOf(address(bob));
        satoshi.approve(address(pristine), type(uint256).max);
        deal(address(satoshi), bob, 40_000 * 10 ** 18);
        pristine.liquidatePosition(1);
        uint256 btcBalanceAfter = pristine.WBTC().balanceOf(address(bob));
        uint256 satoshiBalanceAfter = satoshi.balanceOf(address(bob));

        // Will be 1 BTC because we changed the storage to 1
        assert(btcBalanceAfter - btcBalanceBefore == 1 * 10 ** 8);
        assert(satoshiBalanceAfter == 0);

        vm.startPrank(alice);
        // Hey at least alice still has 40k, not bad
        assert(satoshi.balanceOf(address(alice)) == 40_000 * 10 ** 18);

        bytes4 selector = Pristine.PositionNotFound.selector;
        bytes memory encodedError = abi.encodeWithSelector(selector, id);
        // Now alice tries to withdraw collat - fail
        vm.expectRevert(encodedError);
        pristine.repay(40_000 * 10 ** 18, id);
        vm.stopPrank();
    }

    // For this test we need to deploy a flashloan receiver contract
    // The receiver will flashloan the required amount to liquidate alice's position
    // It then will receive the btc, which it has to sell for satoshi to repay the loan
    // In order to sell, we need to deploy a uniV2 pool and seed it with liquidity
    function test_liquidateSuccessUsingFlashloan() public {
        uint256 btcPrice = pristine.getCollatPrice();
        deal(address(pristine.WBTC()), address(this), 10000 * 10 ** 8);
        deal(address(satoshi), address(this), btcPrice * 10000 * 10 ** 18);
        pristine.WBTC().approve(address(router), 10000 * 10 ** 8);
        satoshi.approve(address(router), btcPrice * 10000 * 10 ** 18);
        router.addLiquidity(
            address(satoshi),
            address(pristine.WBTC()),
            btcPrice * 10000 * 10 ** 18,
            10000 * 10 ** 8,
            0,
            0,
            address(this),
            block.timestamp + 1
        );
        receiver = new FlashloanReceiver();

        vm.startPrank(alice);
        pristine.WBTC().approve(address(pristine), 110 * 10 ** 8);
        uint256 id = pristine.open(110 * 10 ** 8);
        uint256 borrowAmount = (100 * btcPrice * 10 ** 18); // Borrow amount for initial collateral ratio > 110%
        pristine.borrow(borrowAmount, id);
        vm.stopPrank();

        // Adjust collateral to make position unhealthy but still profitable to liquidate
        uint256 adjustedCollatAmount = 105 * 10 ** 8; // Adjusted collateral for collateral ratio between 100% and 110%
        stdstore
            .target(address(pristine))
            .sig("Positions(uint256)")
            .with_key(1)
            .depth(2)
            .checked_write(adjustedCollatAmount);

        assert(!pristine.checkPositionHealth(id));

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encode(id);
        data[1] = abi.encode(address(pristine));
        data[2] = abi.encode(address(router));
        receiver.flashloan(address(satoshi), borrowAmount, data);
        receiver.withdraw(address(satoshi));
        assert(satoshi.balanceOf(address(this)) > 0); // Asserting any profit
        emit log_named_uint(
            "liquidation profit",
            satoshi.balanceOf(address(receiver)) / 10 ** 18
        );
    }
}
