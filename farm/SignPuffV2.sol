// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../core/SafeOwnable.sol';
import '../core/Verifier.sol';

contract SignPuffV2 is SafeOwnable, Verifier {

    event SignIn(uint nonce, address user, uint taskType, uint subTaskType, uint score, uint timestamp);

    mapping(bytes32 => bool) usedMessage;

    constructor(address verifier) Verifier(verifier) {
    }

    function signIn(
        uint nonce,
        uint taskType,
        uint subTaskType,
        uint score,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 data = keccak256(
            abi.encodePacked(address(this), nonce, msg.sender, taskType, subTaskType, score)
        );
        bytes32 message = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", data)
        );
        require(!usedMessage[message], "already sign");
        require(verifier != address(0) && ecrecover(message, v, r, s) == verifier, "signature failed");
        emit SignIn(nonce, msg.sender, taskType, subTaskType, score, block.timestamp);
    }
}
