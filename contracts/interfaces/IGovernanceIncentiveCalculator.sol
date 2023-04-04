// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBasisAsset.sol";

interface IGovernanceIncentiveCalculator {
    function calculateGrowth(address vault) external view returns (uint256);
}
