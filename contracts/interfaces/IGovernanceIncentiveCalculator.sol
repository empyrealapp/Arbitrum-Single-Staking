// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBasisAsset.sol";

interface IGovernanceIncentiveCalculator {
    function calculateGrowth(
        uint256 firmPriceInArb,
        address vault,
        IBasisAsset arbitrum
    ) external view returns (uint256);
}
