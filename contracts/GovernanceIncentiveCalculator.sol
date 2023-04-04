// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/ICamelotRouter.sol";

contract GovernanceIncentiveCalculator is Ownable {
    uint256 APR = 500;
    ICamelotRouter router;
    address public USDC;
    address public arbitrum;
    address public firmament;

    uint public firmamentPriceInArb;

    constructor(
        ICamelotRouter _router,
        address _USDC,
        address _arbitrum,
        address _firmament
    ) {
        router = _router;
        USDC = _USDC;
        arbitrum = _arbitrum;
        firmament = _firmament;
    }

    function update() public onlyOwner {
        address[] memory route = new address[](3);
        route[0] = address(firmament);
        route[1] = address(USDC);
        route[2] = address(arbitrum);
        firmamentPriceInArb = router.getAmountsOut(1 ether, route)[2];
    }

    function calculateGrowth(address vault) external view returns (uint256) {
        uint value = IERC20(arbitrum).balanceOf(vault);
        uint growth = (value * APR) / (10000 * 365 * 2);
        uint firmAmount = (growth * 1e18) / firmamentPriceInArb;
        return firmAmount;
    }
}
