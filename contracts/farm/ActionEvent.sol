// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../core/ReceiverCore.sol';
import '../core/SafeOwnable.sol';
import '../interfaces/IWETH.sol';
import '../core/TimeCore.sol';

contract ActionEvent is SafeOwnable, TimeCore, ReceiverCore {

    event Action(address user, IERC20 token, uint action, uint price, uint amount, uint total, bytes data, uint timestamp);

    uint constant public PRICE_BASE = 10 ** 18;

    mapping(IERC20 => mapping(uint => uint)) public actions;
    mapping(IERC20 => mapping(uint => bool)) public actionsEnable;

    constructor(address _receiver, IWETH _weth) ReceiverCore(_receiver, _weth) {
    }

    modifier LegalAction(uint action) {
        require(action > 0, "illegal action");
        _;
    }

    function addAction(IERC20 _token, uint _action, uint _price) external onlyOwner {
        actions[_token][_action] = _price;
        actionsEnable[_token][_action] = true;
    }

    function delAction(IERC20 _token, uint _action) external onlyOwner {
        delete actions[_token][_action];
        delete actionsEnable[_token][_action];
    }

    function doAction(IERC20 _token, uint _action, uint _amount, bytes memory data) external payable LegalAction(_action) RightTime {
        require(actionsEnable[_token][_action], "not support");
        uint price = actions[_token][_action];
        require(price > 0, "illegal action");
        uint total = price * _amount / PRICE_BASE;
        if (total > 0) {
            require(sendToReceiver(_token, msg.sender, total) == total, "illegal amount");
        }
        emit Action(msg.sender, _token, _action, price, _amount, total, data, block.timestamp);
        require(msg.value == 0, "illegal native token");
        //emit Action(_token, _action, price, _amount, total, 100);
    }

}
