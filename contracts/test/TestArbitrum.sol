// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TestArbitrum is ERC20Burnable {
    constructor() ERC20("Arbitrum", "ARB") {
        _mint(msg.sender, 1e9 * 10 ** decimals());
    }

    function delegate(address delegatee) public {
        // no op
    }
}
