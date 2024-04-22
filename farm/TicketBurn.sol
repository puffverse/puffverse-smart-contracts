// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../interfaces/IBurnableERC721.sol';
import '../core/SafeOwnable.sol';
import '../core/Verifier.sol';

contract TicketBurn is SafeOwnable {

    event BurnReward(uint nonce, address user, uint[] burnIds, address nft, uint rewardId);

    IBurnableERC721 public immutable nft;
    uint public immutable startAt;
    uint public immutable finishAt;

    uint public nonce;

    constructor(IBurnableERC721 _nft, uint _startAt, uint _finishAt) {
        require(address(_nft) != address(0), "illegal nft");
        nft = _nft;
        require(_startAt > block.timestamp && _finishAt > _startAt, "illegal time");
        startAt = _startAt;
        finishAt = _finishAt;
    }
    
    modifier AlreadyBegin() {
        require(block.timestamp >= startAt, "not begin");
        _;
    }
    
    modifier NotFinish() {
        require(block.timestamp <= finishAt, "already finish");
        _;
    }

    function burn(uint [] memory _burnIds, address _burnNFT, uint _rewardId) external AlreadyBegin NotFinish {
        for (uint i = 0; i < _burnIds.length; i ++) { 
            nft.burn(msg.sender, _burnIds[i]);
        }
        nonce ++;
        emit BurnReward(nonce, msg.sender, _burnIds, _burnNFT, _rewardId);
    }
}
