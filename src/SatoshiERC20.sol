// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract Satoshi is ERC20 {
    modifier onlyPristine() {
        require(msg.sender == pristine);
        _;
    }

    address public immutable pristine;

    constructor(address _pristine) ERC20("Satoshi", "STS") {
        pristine = _pristine;
    }

    function mint(address to, uint256 amount) public onlyPristine {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyPristine {
        _burn(from, amount);
    }

    function flashloan(uint256 amount, bytes[] memory data) public {
        _mint(msg.sender, amount);
        (bool success, ) = address(msg.sender).call(
            abi.encodeWithSignature("execute(bytes[])", data)
        );
        require(success, "CALLER_MISSING_FLASHLOAN_INTERFACE");
        _burn(msg.sender, amount);
    }
}
