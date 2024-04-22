// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import './SafeOwnableInterface.sol';

abstract contract Operatable is SafeOwnableInterface {

    event OperaterChanged(address operater, bool available);

    mapping(address => bool) public operaters;

    function _addOperator(address _operater) internal {
        require(!operaters[_operater], "already operater");
        operaters[_operater] = true;
        emit OperaterChanged(_operater, true);
    }

    function addOperater(address _operater) external onlyOwner {
        _addOperator(_operater);
    }

    function delOperater(address _operater) external onlyOwner {
        require(operaters[_operater], "not a operater");
        delete operaters[_operater];
        emit OperaterChanged(_operater, false);
    }

    modifier onlyOperater() {
        require(operaters[msg.sender], "only operater can do this");
        _;
    }

    modifier onlyOperaterSignature(bytes32 _hash, uint8 _v, bytes32 _r, bytes32 _s) {
        address verifier = ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)), _v, _r, _s);
        require(operaters[verifier], "operater verify failed");
        _;
    }

    modifier onlyOperaterOrOperaterSignature(bytes32 _hash, uint8 _v, bytes32 _r, bytes32 _s) {
        if (!operaters[msg.sender]) {
            address verifier = ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)), _v, _r, _s);
            require(operaters[verifier], "operater verify failed");
        }
        _;
    }

}
