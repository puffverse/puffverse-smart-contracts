// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '../interfaces/IPuffERC20.sol';

contract PuffERC20 is ERC20Capped, AccessControlEnumerable, IPuffERC20 {

    uint256 public constant MAX_SUPPLY = 10 * 10 ** 8 * 10 ** 18;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20Capped(MAX_SUPPLY) ERC20("PUFF", "PUFF") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }


    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) returns (uint) {
        amount = Math.min(amount, MAX_SUPPLY - totalSupply());
        _mint(to, amount);
        return amount; 
    }
}
