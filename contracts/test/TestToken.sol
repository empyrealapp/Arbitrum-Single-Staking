// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TestToken is ERC20Burnable {
    uint8 decimals_;

    constructor(uint8 _decimals) ERC20("Test", "TEST") {
        decimals_ = _decimals;
        _mint(msg.sender, 1e9 * 10 ** decimals_);
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
