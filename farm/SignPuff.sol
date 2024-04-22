// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../interfaces/IBurnableERC721.sol';
import '../core/SafeOwnable.sol';

contract SignPuff is SafeOwnable {

    event SignIn(address user, uint continueNum, uint totalNum, uint timestamp);

    uint public constant BEGIN_TIME = 0;
    uint public constant interval = 1 days;

    mapping(address => uint) continueNum;
    mapping(address => uint) totalNum;
    mapping(address => uint) lastTime;

    function signIn() external {
        uint lastCrycle = timeToCrycle(lastTime[msg.sender]);
        uint currentCrycle = timeToCrycle(block.timestamp);
        require(currentCrycle > lastCrycle, "already signed puff");
        totalNum[msg.sender] = totalNum[msg.sender] + 1;
        lastTime[msg.sender] = block.timestamp;
        if (currentCrycle - lastCrycle == 1) {
            continueNum[msg.sender] = continueNum[msg.sender] + 1;
        } else {
            continueNum[msg.sender] = 1;
        }
        emit SignIn(msg.sender, continueNum[msg.sender], totalNum[msg.sender], block.timestamp);
    }

    function signInInfo(address _user) external view returns(bool available, uint userContinueNum, uint userTotalNum) {
        uint lastCrycle = timeToCrycle(lastTime[_user]);
        uint currentCrycle = timeToCrycle(block.timestamp);
        if (lastCrycle == currentCrycle) {
            available = false;
            userContinueNum = continueNum[_user];
            userTotalNum = totalNum[_user];
        } else {
            available = true;
            if (currentCrycle - lastCrycle == 1) {
                userContinueNum = continueNum[_user];
            } else {
                userContinueNum = 0;
            }
            userTotalNum = totalNum[_user];
        }
    }

    function timeToCrycle(uint _timestamp) public pure returns(uint _crycle) {
        return (_timestamp - BEGIN_TIME) / interval;
    }

    struct ImportUserInfo {
        address user;
        uint continueNum;
        uint totalNum;
        uint lastTime;
    }

    function importData(ImportUserInfo[] memory importUserInfos) external onlyOwner {
        for (uint i = 0; i < importUserInfos.length; i ++) {
            ImportUserInfo memory importUserInfo = importUserInfos[i];
            require(lastTime[importUserInfo.user] == 0, "already import");
            continueNum[importUserInfo.user] = importUserInfo.continueNum;
            totalNum[importUserInfo.user] = importUserInfo.totalNum;
            lastTime[importUserInfo.user] = importUserInfo.lastTime;
        }
    }
}
