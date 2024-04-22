// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '../core/SafeOwnable.sol';

contract MockERC1155 is SafeOwnable, ERC1155 {

    string public name;
    string public symbol;
    function setURI(string memory _uri) external onlyOwner {
        _setURI(_uri);
    }

    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) ERC1155(_uri) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address _to, uint _tokenId, uint _amount) external onlyOwner {
        _mint(_to, _tokenId, _amount, new bytes(0));
    }
}
