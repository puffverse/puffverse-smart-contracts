// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../core/SafeOwnable.sol';
import '../core/Verifier.sol';

contract PuffOnChain is SafeOwnable, Verifier {

    event Operation(address indexed user, uint indexed nonce, uint indexed operationType, bytes data);

    mapping(bytes32 => bool) usedNonce;

    constructor(address verifier) Verifier(verifier) {
    }

    function getUsedNonce(uint nonce, uint operationType) public view returns (bool) {
        bytes32 typeNonce = keccak256(abi.encodePacked(nonce, operationType));
        return usedNonce[typeNonce];
    }

    function operate(uint nonce, uint operationType, bytes calldata data, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 typeNonce = keccak256(abi.encodePacked(nonce, operationType));
        require(!usedNonce[typeNonce], "already used");
        usedNonce[typeNonce] = true;
        require(
            ecrecover(
                keccak256(abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32", 
                    keccak256(abi.encodePacked(address(this), msg.sender, nonce, operationType, data))
                )), 
                v, r, s
            ) == verifier,
            "verify failed"
        );
        emit Operation(msg.sender, nonce, operationType, data);
    }

}
