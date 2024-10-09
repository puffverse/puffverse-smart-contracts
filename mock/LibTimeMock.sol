// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../libraries/LibTime.sol";

contract LibTimeMock {
    using LibTime for uint256;

    function timestampToDateStr(uint timestamp) external pure returns (string memory) {
        return timestamp.timestampToDateStr();
    }
}
