// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '../core/SafeOwnable.sol';

contract MockNFTV2 is SafeOwnable, ERC721Enumerable {

    string public baseURI;

    function _baseURI() internal view override virtual returns (string memory) {
        return baseURI;
    }

    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) ERC721(_name, _symbol) {
        baseURI = _uri;
    }

    function mint(address _to, uint _tokenId) external onlyOwner {
        _mint(_to, _tokenId);
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }
}
