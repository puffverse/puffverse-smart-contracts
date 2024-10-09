// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IVault {
    function withdraw(address _token, uint _tokenId, uint _amount, address _recipient) external;
}
