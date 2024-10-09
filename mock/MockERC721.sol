// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';

contract MockERC721 is ERC721Enumerable {

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

    function mint(address _to, uint _tokenId) external {
        _mint(_to, _tokenId);
    }

    function setBaseURI(string memory _uri) external {
        baseURI = _uri;
    }
}
