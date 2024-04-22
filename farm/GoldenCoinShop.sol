// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../core/SafeOwnable.sol';
import '../core/TimeCore.sol';

contract GoldenCoinShop is SafeOwnable, TimeCore {
    using SafeERC20 for IERC20;

    uint constant public interval = 1 days;

    event ItemChanged(uint id, IERC20 token, uint cost, uint reward, bool available);
    event ReceiverChanged(address oldReceiver, address newReceiver);
    event Buy(uint id, IERC20 token, uint cost, uint reward, uint timestamp);
    event DailyGoldenLimitChanged(uint oldValue, uint newValue);

    struct Item {
        uint id;
        IERC20 token;
        uint cost;
        uint reward;
        uint dailyLimit;
        bool available;
    }

    IERC20 immutable public WETH;
    Item[] public items;
    address payable public receiver;
    mapping (uint => mapping(address => uint)) public userLast;
    mapping (uint => mapping(address => uint)) public userBuyed;
    uint public globalLast;
    uint public globalBuyed;
    uint public dailyGoldenLimit;

    constructor(IERC20 _WETH, address payable _receiver) {
        WETH = _WETH;
        require(_receiver != address(0), "illegal receiver");
        emit ReceiverChanged(receiver, _receiver);
        receiver = _receiver;
    }

    function addItem(IERC20 _token, uint _cost, uint _reward, uint _dailyLimit) internal {
        require(address(_token) != address(0), "illegal token");
        items.push(Item({
            id: items.length,
            token: _token,
            cost: _cost,
            reward: _reward,
            dailyLimit: _dailyLimit,
            available: true
        }));
        unchecked {
            emit ItemChanged(items.length - 1, _token, _cost, _reward, true);
        }
    }

    function addItems(IERC20[] memory _tokens, uint[] memory _costs, uint[] memory _rewards, uint[] memory _dailyLimits) external onlyOwner {
        require(_tokens.length == _costs.length && _costs.length == _rewards.length && _rewards.length == _dailyLimits.length, "illegallength"); 
        unchecked {
            for (uint i = 0; i < _tokens.length; i ++) {
                addItem(_tokens[i], _costs[i], _rewards[i], _dailyLimits[i]);
            }
        }
    }

    function disableItems(uint[] memory _ids) external onlyOwner {
        unchecked {
            for (uint i = 0; i < _ids.length; i ++) {
                require(_ids[i] < items.length, "illegal id");
                Item storage item = items[_ids[i]];
                item.available = false;
                emit ItemChanged(item.id, item.token, item.cost, item.reward, item.available);
            }
        }
    }

    function enableItems(uint[] memory _ids) external onlyOwner {
        unchecked {
            for (uint i = 0; i < _ids.length; i ++) {
                require(_ids[i] < items.length, "illegal id");
                Item storage item = items[_ids[i]];
                item.available = true;
                emit ItemChanged(item.id, item.token, item.cost, item.reward, item.available);
            }
        }
    }

    function changeItem(uint _id, uint _cost, uint _reward, uint _dailyLimit, bool _available) internal {
        require(_id < items.length, "illegal id");
        Item storage item = items[_id];
        item.cost = _cost;
        item.reward = _reward;
        item.dailyLimit = _dailyLimit;
        item.available = _available;
        emit ItemChanged(_id, item.token, item.cost, item.reward, item.available);
    }

    function changeItems(Item[] memory _items) external onlyOwner {
        for (uint i = 0; i < _items.length; i ++) {
            changeItem(_items[i].id, _items[i].cost, _items[i].reward, _items[i].dailyLimit, _items[i].available);
        }
    }

    function changeReciever(address payable _receiver) external onlyOwner {
        require(_receiver != address(0), "illegal receiver");
        emit ReceiverChanged(receiver, _receiver);
        receiver = _receiver;
    }

    function changeDailyGoldenLimit(uint _limit) external onlyOwner {
        emit DailyGoldenLimitChanged(dailyGoldenLimit, _limit);
        dailyGoldenLimit = _limit;
    }

    function buy(uint _id, IERC20 _token, uint _cost, uint _reward) external payable RightTime {
        require(_id < items.length, "illegal id");
        Item memory item = items[_id];
        require(item.available, "item not exist");
        require(item.token == _token && item.cost == _cost && item.reward == _reward, "item changed");
        uint currentDay = block.timestamp / interval;

        uint remain = item.dailyLimit;
        if (userLast[_id][msg.sender] >= currentDay) {
            remain = item.dailyLimit - userBuyed[_id][msg.sender];
        } else {
            userBuyed[_id][msg.sender] = 0;
            userLast[_id][msg.sender] = currentDay;
        }
        require(remain > 0, "already full");

        uint dailyBuyed = 0;
        if (globalLast >= currentDay) {
            dailyBuyed = globalBuyed;
        } else {
            globalLast = currentDay;
            globalBuyed = 0;
        }
        require(dailyBuyed + _reward <= dailyGoldenLimit, "already full");
        if (_token == WETH) {
            require(_cost == msg.value, "illegal cost");
            receiver.transfer(_cost);
        } else {
            _token.safeTransferFrom(msg.sender, receiver, _cost);
        }
        userBuyed[_id][msg.sender] += 1;
        globalBuyed += _reward;
        emit Buy(_id, _token, _cost, _reward, block.timestamp);
    }

    function userDailyBuyed(uint _id, address _user) external view returns (uint) {
        uint currentDay = block.timestamp / interval;
        if (userLast[_id][_user] >= currentDay) {
            return userBuyed[_id][_user];
        } else {
            return 0;
        }
    }

    function globalDailyBuyed() external view returns (uint) {
        uint currentDay = block.timestamp / interval;
        if (globalLast >= currentDay) {
            return globalBuyed;
        } else {
            return 0;
        }
    }

    function itemLength() public view returns (uint length) {
        for (uint i = 0; i < items.length; i ++) {
            if (items[i].available) {
                unchecked {
                    length += 1;
                }
            }
        }
    }

    function itemArrayLength() external view returns (uint) {
        return items.length;
    }

    function allItems() external view returns (Item[] memory itemList) {
        itemList = new Item[](itemLength()); 
        uint currentIndex = 0;
        for (uint i = 0; i < items.length; i ++) {
            if (items[i].available) {
                itemList[currentIndex].id = items[i].id;
                itemList[currentIndex].token = items[i].token;
                itemList[currentIndex].cost = items[i].cost;
                itemList[currentIndex].reward = items[i].reward;
                itemList[currentIndex].dailyLimit = items[i].dailyLimit;
                itemList[currentIndex].available = items[i].available;
                unchecked {
                    currentIndex += 1;
                }
            }
        }
    }

}
