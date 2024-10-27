// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/ITokenLocker.sol';
import '../interfaces/IPuffERC20.sol';

contract TokenLocker is ITokenLocker {
    using SafeERC20 for IPuffERC20;

    event Claim(address receiver, uint amount, uint timestamp);

    IPuffERC20 public immutable TOKEN;
    address public immutable receiver;
    uint256 public immutable firstReleaseAmount;
    uint256 public immutable startTime;
    uint256 public immutable cycleNum;
    uint256 public immutable interval;
    uint256 public immutable cycleReleaseAmount;

    uint256 public released;


    constructor(
        IPuffERC20 token,
        address _receiver,
        uint256 _firstReleaseAmount,
        uint256 _startTime,
        uint256 _cycleNum,
        uint256 _interval,
        uint256 _cycleReleaseAmount
    ) {
        TOKEN = token;
        require(_receiver != address(0), "receiver cannot be zero address");
        receiver = _receiver;
        firstReleaseAmount = _firstReleaseAmount;
        startTime = _startTime;
        cycleNum = _cycleNum;
        interval = _interval;
        cycleReleaseAmount = _cycleReleaseAmount;
    }

    function available() public view returns (uint256) {
        uint amount = firstReleaseAmount;
        for (uint cycle = 0; cycle <= cycleNum; cycle ++) {
            uint releaseTime = startTime + cycle * interval + 1;
            if (block.timestamp >= releaseTime) {
                amount += cycleReleaseAmount;
            } else {
                break;
            }
        }
        return amount - released;
    }

    function claim() external {
        uint currentAvailable = available();
        if (currentAvailable > 0) {
            uint currentBalance = TOKEN.balanceOf(address(this));
            if (currentAvailable > currentBalance) {
                currentAvailable = currentBalance;
            }
            TOKEN.safeTransfer(receiver, currentAvailable);            
            released += currentAvailable;
            emit Claim(receiver, currentAvailable, block.timestamp);
        }
    }
}
