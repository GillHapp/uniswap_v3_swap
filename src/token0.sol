//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract token0 is ERC20 {
    constructor() ERC20("Token0", "TK0") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}