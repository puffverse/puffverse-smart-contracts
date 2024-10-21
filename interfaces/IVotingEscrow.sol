// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IVotingEscrow {

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    struct LockedBalance {
        uint begin;
        int128 amount;
        int128 point;
        uint end;
    }

    function nftPointEpoch(uint tokenId) external view returns (uint);
    function nftPointHistory(uint tokenId, uint loc) external view returns (int128, int128, uint256, uint256);
    function pointHistory(uint loc) external view returns (int128, int128, uint256, uint256);
    function checkpoint() external;
    function nftOwner(uint tokenId) external view returns (address);
    function LOCK_TOKEN() external view returns(IERC20);
    function BOOST_NFT() external view returns(IERC721);
    function epoch() external view returns(uint256);
    function totalLocked() external view returns(uint256);

    function createLock(
        uint _lockAmount, 
        uint _lockDuration, 
        address _for, 
        uint _boostTokenId
    ) external returns (uint);

    function forcePenaltyAmount(uint timestamp) external view returns (uint);
    function totalPowerAt(uint timestamp) external view returns (uint);
}
