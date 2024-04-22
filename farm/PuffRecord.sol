// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

contract PuffRecord {

    uint public nonce = 0;
    event Record(uint nonce, uint tokenId, uint tokenType, address user);

    constructor() {
        nonce = 1;
    }

    function search(uint tokenId, uint tokenType) external {
        emit Record(nonce ++, tokenId, tokenType, msg.sender);
    }

}
