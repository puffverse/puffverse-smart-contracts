// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import './IERC721CoreV2.sol';

interface IMintableERC721V4 is IERC721CoreV2 {

    function mint(address _to, uint _num) external;

    function mintById(address _to, uint _tokenId) external;

    function exists(uint _tokenId) external view returns(bool);

}

