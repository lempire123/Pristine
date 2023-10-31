// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/Pristine.sol";
import "src/SatoshiERC20.sol";
import {ISatoshi} from "src/interfaces/ISatoshiInterface.sol";
import {IUniswapV2Router02} from "lib/amm/interfaces/IUniswapV2Router02.sol";

contract FlashloanReceiver {
    function flashloan(
        address sat,
        uint256 amount,
        bytes[] memory data
    ) external {
        (bool success, ) = sat.call(
            abi.encodeWithSignature("flashloan(uint256,bytes[])", amount, data)
        );
        require(success, "CALL_FAILED");
    }

    // Array of 32byte values
    // 1st 32 bytes = position id to liquidate
    // 2nd 32 bytes = address of pristine contract
    // 3rd 32 bytes = address of router
    function execute(bytes[] memory data) external {
        // parse bytes
        uint256 id = abi.decode(data[0], (uint256));
        uint256 debtAmount = abi.decode(data[1], (uint256));
        address pristine = abi.decode(data[2], (address));
        address router = abi.decode(data[3], (address));
        // liquidate
        Pristine(pristine).liquidatePosition(id, debtAmount);
        address[] memory path = new address[](2);
        path[0] = address(Pristine(pristine).WBTC());
        path[1] = address(Pristine(pristine).Satoshi());
        // Now we have the collateral, we can swap it for the debt
        Pristine(pristine).WBTC().approve(router, type(uint256).max);
        IUniswapV2Router02(router).swapExactTokensForTokens(
            Pristine(pristine).WBTC().balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp + 1
        );
    }

    function withdraw(address satoshi) external {
        ISatoshi(satoshi).transfer(
            msg.sender,
            ISatoshi(satoshi).balanceOf(address(this))
        );
    }
}
