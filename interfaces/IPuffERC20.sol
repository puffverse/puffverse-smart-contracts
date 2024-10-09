// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

interface IPuffERC20 is IERC20Metadata {
    function mint(address to, uint amount) external returns(uint);
}

