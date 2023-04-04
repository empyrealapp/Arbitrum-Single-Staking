// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IManager {
    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function getEmpyrealPrice() external view returns (uint256);
}
