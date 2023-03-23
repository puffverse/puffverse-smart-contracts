// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import './IMintableERC721V3.sol';

interface INFTShop {

    function userBuyed(address user, IMintableERC721V3 nft) external view returns (uint);

}

