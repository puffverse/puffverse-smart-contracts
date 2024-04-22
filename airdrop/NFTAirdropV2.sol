// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interfaces/IMintableERC721V2.sol';
import '../core/SafeOwnable.sol';

contract NFTAirdropV2 is SafeOwnable {
    using SafeERC20 for IERC20;

    uint public nonce;

    function ERC721Mint(uint _startNonce, IMintableERC721V2 _token, address[] memory _users, uint[] memory _tokenIds) external onlyOwner {
        require(_startNonce > nonce, "already done");
        require(_users.length > 0 && _users.length == _tokenIds.length, "illegal length");
        for (uint i = 0; i < _users.length; i ++) {
            _token.mintById(_users[i], _tokenIds[i]);
        }
        nonce = _startNonce + _users.length - 1;
    }

    function ERC721Transfer(uint _startNonce, address vault, IMintableERC721V2 _token, address[] memory _users, uint[] memory _tokenIds) external onlyOwner {
        require(_startNonce > nonce, "already done");
        require(_users.length > 0 && _users.length == _tokenIds.length, "illegal length");
        if (vault == address(0)) {
            vault = msg.sender;
        }
        for (uint i = 0; i < _users.length; i ++) {
            _token.safeTransferFrom(vault, _users[i], _tokenIds[i]);
        }
        nonce = _startNonce + _users.length - 1;
    }
}
