// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './SafeOwnableInterface.sol';
import '../interfaces/IWETH.sol';
import './TransferCore.sol';

abstract contract ReceiverCore is TransferCore, SafeOwnableInterface {
    using SafeERC20 for IERC20;

    event NewReceiver(address oldValue, address newValue);

    address public receiver;

    constructor(address _receiver, IWETH _weth) TransferCore(_weth) {
        require(_receiver != address(0), "illegal receiver");
        receiver = _receiver;
        emit NewReceiver(address(0), _receiver);
    }

    function setReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0) && _receiver != receiver, "illegal receiver");
        emit NewReceiver(receiver, _receiver);
        receiver = _receiver;
    }

    function sendToReceiver(IERC20 _token, address _user, uint _amount) internal returns (uint) {
        uint balanceBefore = tokenBalance(_token, receiver);
        tokenTransferFrom(_token, _user, receiver, _amount);
        uint balanceAfter = tokenBalance(_token, receiver);
        return balanceAfter - balanceBefore;
    }

}
