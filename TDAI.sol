// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TDAI is ERC20 {
    address public owner;

    constructor() ERC20("Thai DAI", "TDAI") {
        owner = msg.sender;
        _mint(msg.sender, 100_000_000 * 10**decimals());
    }

    function faucet(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == owner, "Not owner");
        _mint(to, amount);
    }
}