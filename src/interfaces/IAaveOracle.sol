// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IAaveOracle {
    function getAssetPrice(address _asset) external view returns (uint256);
}
