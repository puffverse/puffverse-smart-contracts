// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import './IERC721Core.sol';

interface IMintableERC721V3 is IERC721Core {

    function mint(address _to, uint _num) external;

    function MAX_SUPPLY() external view returns (uint);

}

