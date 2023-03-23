// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import './SafeOwnableInterface.sol';

abstract contract VerifierV2 is SafeOwnableInterface {

    event VerifierChanged(address oldVerifier, address newVerifier);

    address public verifier;

    function _setVerifier(address _verifier) internal {
        require(_verifier != address(0), "illegal verifier");
        emit VerifierChanged(verifier, _verifier);
        verifier = _verifier;
    }

    function setVerifier(address _verifier) external onlyOwner {
        _setVerifier(_verifier);
    }

}
