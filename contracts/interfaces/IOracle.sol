// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUniswapV2Pair.sol";

interface IOracle {
    function pair() external view returns (IUniswapV2Pair);

    function update() external;

    function consult(
        address _token,
        uint256 _amountIn
    ) external view returns (uint144 amountOut);

    function twap(
        address _token,
        uint256 _amountIn
    ) external view returns (uint144 _amountOut);
}
