// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract MockGovernanceIncentiveCalculator is Ownable {
    uint APR = 500;
    uint public firmamentPriceInArb = 147946065751659741874;
    address arbitrum;

    constructor(
        address _router,
        address _USDC,
        address _arbitrum,
        address _firmament
    ) {
        arbitrum = _arbitrum;
    }

    function update() public onlyOwner {}

    function calculateGrowth(address vault) external view returns (uint256) {
        uint value = IERC20(arbitrum).balanceOf(vault);
        uint growth = (value * APR) / (10000 * 365 * 2);
        uint firmAmount = (growth * 1e18) / firmamentPriceInArb;
        return firmAmount;
    }
}
