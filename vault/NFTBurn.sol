// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '../core/SafeOwnable.sol';

contract NFTBurn is SafeOwnable, IERC721Receiver {

    event Burned(IERC721 token, uint tokenId, uint index, bytes data);

    address public verifier;

    constructor(address _verifier) {
        verifier = _verifier;
    }

    function setVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
    }

    function burn(IERC721[] memory _tokens, uint[] memory _tokenIds, bytes calldata _data, uint8 _v, bytes32 _r, bytes32 _s) external {
        require(_tokens.length == _tokenIds.length, "illegal length");
        require(
            ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(address(this), msg.sender, _tokens, _tokenIds, _data)))), _v, _r, _s) == verifier && verifier != address(0),
            "verify failed"
        );
        for (uint i = 0; i < _tokens.length; i ++) {
            IERC721 token = _tokens[i];
            uint tokenId = _tokenIds[i];
            token.transferFrom(msg.sender, address(this), tokenId);
            emit Burned(token, tokenId, i, _data);
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override pure returns (bytes4) {
        if (false) {
            operator;
            from;
            tokenId;
            data;
        }
        return 0x150b7a02;
    }
}
