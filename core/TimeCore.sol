// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import './SafeOwnableInterface.sol';

abstract contract TimeCore is SafeOwnableInterface {

    event StartAtChanged(uint oldValue, uint newValue);
    event FinishAtChanged(uint oldValue, uint newValue);

    uint public startAt;
    uint public finishAt;

    constructor() {
        startAt = 0;
        emit StartAtChanged(0, startAt);
        finishAt = type(uint).max;
        emit FinishAtChanged(0, finishAt);
    }

    function _setStartAt(uint _startAt) internal {
        emit StartAtChanged(startAt, _startAt);
        startAt = _startAt;
    }

    function _setFinishAt(uint _finishAt) internal {
        emit FinishAtChanged(finishAt, _finishAt);
        finishAt = _finishAt;
    }

    function setStartAt(uint _startAt) external onlyOwner {
        _setStartAt(_startAt);
    }

    function setFinishAt(uint _finishAt) external onlyOwner {
        _setFinishAt(_finishAt);
    }

    modifier RightTime() {
        require(block.timestamp >= startAt && block.timestamp <= finishAt, "illegal time");
        _;
    }

    modifier AlreadyBegin() {
        require(block.timestamp >= startAt, "not begin");
        _;
    }

    modifier NotFinish() {
        require(block.timestamp <= finishAt, "already finish");
        _;
    }

}
