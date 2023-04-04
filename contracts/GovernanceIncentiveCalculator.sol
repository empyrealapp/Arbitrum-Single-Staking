// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IBasisAsset.sol";
import "hardhat/console.sol";

contract GovernanceIncentiveCalculator {
    uint256 APR = 400;

    function calculateGrowth(
        uint256 arbitrumPrice,
        uint256 firmamentPriceInArb,
        address vault,
        IBasisAsset arbitrum
    ) external view returns (uint256) {
        uint value = (arbitrumPrice * arbitrum.balanceOf(vault)) / 1e18;
        uint growth = (value * APR) / (10000 * 365 * 2);
        uint firmAmount = (growth * 1e18) / firmamentPriceInArb;
        return firmAmount;
    }
}
