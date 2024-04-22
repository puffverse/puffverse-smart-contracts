// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';


contract PuffGoMarket is Ownable, Initializable {
    address public usdt;

    struct Commodity {
        uint usdtAmount;
        uint coinType;
        uint coinAmount;
        uint giveAmount;
    }

    mapping(uint => Commodity) public commodityList;
    mapping(uint => bool) public commodityStatus;

    uint orderId = 0;

    address public receiving;

    event Recharge(uint oid, address sender, uint uid, uint commType, uint usdt, uint coin, uint give);

    function initialize(
        address _usdt,
        address _owner,
        address _receiving
    ) external initializer {
        usdt = _usdt;
        receiving = _receiving;
        _transferOwnership(_owner);
    }

    function addCommodity(uint _type, uint _usdt, uint _coinType, uint _coin, uint _give) external onlyOwner {
        require(_usdt > 0 && _coin > 0, "Invalid values");
        Commodity storage c = commodityList[_type];
        c.coinType = _coinType;
        c.giveAmount = _give;
        c.coinAmount = _coin;
        c.usdtAmount = _usdt;
        commodityStatus[_type] = true;
    }

    function setCommodity(uint _type, bool _bool) external onlyOwner {
        commodityStatus[_type] = _bool;
    }

    function setReceiving(address _receiving) external onlyOwner {
        receiving = _receiving;
    }

    function setUsdt(address _usdt) external onlyOwner {
        usdt = _usdt;
    }


    function recharge(uint commodityType, uint uid) external {
        require(commodityStatus[commodityType], "Invalid commodity type");
        Commodity memory c = commodityList[commodityType];
        IERC20(usdt).transferFrom(msg.sender, receiving, c.usdtAmount);
        emit Recharge(orderId++, msg.sender, uid, commodityType, c.usdtAmount, c.coinAmount, c.giveAmount);
    }
}