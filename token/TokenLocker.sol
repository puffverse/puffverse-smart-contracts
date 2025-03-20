// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/ITokenLocker.sol';
import '../interfaces/IPuffERC20.sol';

contract TokenLocker is ITokenLocker,AccessControlEnumerable {
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
    uint256 public adjustTime;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor(
        IPuffERC20 token,
        address _receiver,
        uint256 _firstReleaseAmount,
        uint256 _startTime,
        uint256 _cycleNum,
        uint256 _interval,
        uint256 _cycleReleaseAmount,
        uint256 _adjustTime,
        address _admin
    ) {
        TOKEN = token;
        require(_receiver != address(0), "receiver cannot be zero address");
        receiver = _receiver;
        firstReleaseAmount = _firstReleaseAmount;
        startTime = _startTime;
        cycleNum = _cycleNum;
        interval = _interval;
        cycleReleaseAmount = _cycleReleaseAmount;
        adjustTime = _adjustTime;
        require(_admin != address(0), "admin address is zero");
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    function changeAdjustTime(uint256 _adjustTime) external onlyRole(ADMIN_ROLE) {
        require(block.timestamp < startTime + adjustTime, "adjustTime change fail1");
        require(block.timestamp < startTime + _adjustTime, "adjustTime change fail2");
        adjustTime = _adjustTime;
    }

    function available() public view returns (uint256) {
        uint amount = firstReleaseAmount;
        for (uint cycle = 0; cycle < cycleNum; cycle ++) {
            uint releaseTime = startTime + adjustTime + cycle * interval + 1;
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
