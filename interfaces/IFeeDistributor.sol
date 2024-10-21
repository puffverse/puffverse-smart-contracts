// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

interface IFeeDistributor {
    function checkpoint() external;
    function claimVE(uint tokenId) external ;
}
