// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../core/TransferCore.sol';
import '../core/SafeOwnable.sol';
import '../interfaces/IWETH.sol';
import '../core/TimeCore.sol';

contract ActionEvent is SafeOwnable, TimeCore, TransferCore, Initializable {

    event Action(address user, IERC20 token, uint action, uint price, uint amount, uint total, bytes data, uint timestamp);

    uint constant public PRICE_BASE = 10 ** 18;

    mapping(IERC20 => mapping(uint => uint)) public actions;
    mapping(IERC20 => mapping(uint => bool)) public actionsEnable;

    address public receiver;
    address public vault;
    uint public vaultPercent = 9000;
    uint public immutable PERCENT_BASE = 10000;

    constructor(IWETH _weth) TransferCore(_weth) {
        _disableInitializers();
    }

    function initialize(address _receiver, address _vault) external initializer {
        _transferOwnership(msg.sender);
        receiver = _receiver;
        vault = _vault;
        vaultPercent = 9000;
    }

    function setReceiver(address _receiver) external onlyOwner {
        receiver = _receiver;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setVaultPercent(uint _percent) external onlyOwner {
        require(_percent <= PERCENT_BASE, "illegal _percent");
        vaultPercent = _percent;
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
            uint vaultAmount = total * vaultPercent / PERCENT_BASE;
            uint receiverAmount = total - vaultAmount;
            if (vaultAmount > 0) {
                tokenTransferFrom(_token, msg.sender, vault, vaultAmount);
            }
            if (receiverAmount > 0) {
                tokenTransferFrom(_token, msg.sender, receiver, receiverAmount); 
            }
        }
        emit Action(msg.sender, _token, _action, price, _amount, total, data, block.timestamp);
        require(msg.value == 0, "illegal native token");
        //emit Action(_token, _action, price, _amount, total, 100);
    }

}
