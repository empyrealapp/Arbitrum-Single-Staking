// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IAuthority {
    function treasury() external view returns (address);

    function controller() external view returns (address);

    function empyreal() external view returns (address);

    function firmament() external view returns (address);

    function horizon() external view returns (address);

    function empyrealMinters(address) external view returns (bool);

    function firmamentMinters(address) external view returns (bool);
}
