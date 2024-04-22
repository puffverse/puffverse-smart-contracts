// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interfaces/IMintableERC721V2.sol';
import '../core/SafeOwnable.sol';

interface IERC721Mint {
    function mint(address to) external returns (uint);
}

contract NFTAirdropV3 is SafeOwnable {

    struct NFTInfo {
        uint tokenId;
        address user;
    }

    function ERC721Mint(IERC721Mint _token, NFTInfo[] memory _nftInfos) external onlyOwner {
        for (uint i = 0; i < _nftInfos.length; i ++) {
            uint nftId = _token.mint(_nftInfos[i].user);
            require(nftId == _nftInfos[i].tokenId, "illegal tokenId");
        }
    }
}
