//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract token1 is ERC20 {
    constructor() ERC20("Token1", "TK1") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}
