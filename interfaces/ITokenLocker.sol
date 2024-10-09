// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface ITokenLocker {
    function available() external view returns (uint256);
    function claim() external;
}

