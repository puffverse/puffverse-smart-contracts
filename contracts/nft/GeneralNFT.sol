// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../core/SafeOwnable.sol';
import '../core/NFTCoreV4.sol';
import '../core/Mintable.sol';
import '../core/Burnable.sol';

contract GeneralNFT is SafeOwnable, NFTCoreV4, Mintable, Burnable {

    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) NFTCoreV4(_name, _symbol, _uri, type(uint).max) Mintable(new address[](0), false) Burnable(new address[](0), false) {
    }

    function mintById(address _to, uint _tokenId) external onlyMinter {
        mintByIdInternal(_to, _tokenId);
    }

    function burn(address _user, uint256 _tokenId) external onlyBurner {
        burnInternal(_user, _tokenId); 
    }
}
