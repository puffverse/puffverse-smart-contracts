// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../interfaces/IMintableERC721V3.sol';
import '../interfaces/INFTShop.sol';
import '../core/SafeOwnable.sol';
import '../core/TimeCore.sol';

contract PuffNewYearClaim is SafeOwnable, TimeCore {

    event ClaimConditionChanged(uint oldValue, uint newValue);
    event TotalSupplyChanged(uint oldValue, uint newValue);
    event Claim(address user, uint nftId);

    IMintableERC721V3 public immutable puffNewYearNFT;
    IMintableERC721V3 public immutable classicNFT;
    INFTShop public immutable nftShop;
    uint public claimCondition;
    mapping(address => uint) public userClaimed;
    uint public totalSupply;
    uint public totalClaimed;

    constructor(IMintableERC721V3 _puffNewYearNFT, IMintableERC721V3 _classicNFT, INFTShop _nftShop, uint _claimCondition, uint _totalSupply) {
        require(address(_puffNewYearNFT) != address(0) && address(_classicNFT) != address(0) && address(_nftShop) != address(0), "illegal nft");
        puffNewYearNFT = _puffNewYearNFT;
        classicNFT = _classicNFT;
        nftShop = _nftShop;
        emit ClaimConditionChanged(claimCondition, _claimCondition);
        claimCondition = _claimCondition;
        require(_totalSupply <= _puffNewYearNFT.MAX_SUPPLY(), "illegal totalSupply");
        emit TotalSupplyChanged(totalSupply, _totalSupply);
        totalSupply = _totalSupply;
    }

    function setClaimCondition(uint _condition) external onlyOwner {
        require(_condition != 0, "illegal value");
        emit ClaimConditionChanged(claimCondition, _condition);
        claimCondition = _condition;
    }

    function setTotalSupply(uint _totalSupply) external onlyOwner {
        require(_totalSupply >= totalClaimed && _totalSupply <= puffNewYearNFT.MAX_SUPPLY(), "illegal value");
        emit TotalSupplyChanged(totalSupply, _totalSupply);
        totalSupply = _totalSupply;
    }

    function available(address _user) public view returns(uint totalNum, uint claimedNum) {
        uint userBuyed = nftShop.userBuyed(_user, classicNFT);
        totalNum = userBuyed / claimCondition;
        claimedNum = userClaimed[_user];
    }

    function claim() external RightTime {
        (uint totalNum, uint claimedNum) = available(msg.sender);
        require(totalNum > claimedNum, "no available");
        uint remain = totalNum - claimedNum;
        require(totalClaimed + remain <= totalSupply, "already executed");
        puffNewYearNFT.mint(msg.sender, remain);
        userClaimed[msg.sender] += remain;
        totalClaimed += remain;
        uint lastTokenId = puffNewYearNFT.totalSupply();
        for (uint i = 0; i < remain; i ++) {
            emit Claim(msg.sender, lastTokenId - 1);
        }
    }
}
