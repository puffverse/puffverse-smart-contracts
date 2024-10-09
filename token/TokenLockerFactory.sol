// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/ITokenLocker.sol';
import '../interfaces/IPuffERC20.sol';
import './TokenLocker.sol';

contract TokenLockerFactory is AccessControlEnumerable {
    using SafeERC20 for IPuffERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IPuffERC20 public immutable TOKEN;

    mapping(uint256 => ITokenLocker) public lockers;

    constructor(
        IPuffERC20 token,
        address admin
    ) {
        TOKEN = token;
        _grantRole(ADMIN_ROLE, admin);
    }

    function createLocker(
        uint256 _index,
        address _receiver,
        uint256 _firstReleaseAmount,
        uint256 _startTime,
        uint256 _cycleNum,
        uint256 _interval,
        uint256 _intervalReleaseAmount
    ) external onlyRole(ADMIN_ROLE) returns (ITokenLocker) {
        bytes32 id = keccak256(abi.encode(_index));
        bytes memory bytecode = abi.encodePacked(
            type(TokenLocker).creationCode,
            abi.encode(
                TOKEN, _receiver, _firstReleaseAmount, _startTime, _cycleNum, _interval, _intervalReleaseAmount
            )
        );
        address locker;
        assembly {
            locker := create2(0, add(bytecode, 0x20), mload(bytecode), id)
            if iszero(extcodesize(locker)) {
                revert(0, 0)
            }
        }
        lockers[_index] = ITokenLocker(locker); 
        return ITokenLocker(locker);
    }

    function chargeLocker(
        uint256 _index,
        uint256 _totalAmount
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        ITokenLocker locker = lockers[_index];
        require(address(locker) != address(0), "not exist");
        TOKEN.mint(address(locker), _totalAmount);
        require(TOKEN.balanceOf(address(locker)) >= _totalAmount, "amount illegal");
        uint available = locker.available();
        if (available > 0) {
            locker.claim();
        }
        return available;
    }
}
