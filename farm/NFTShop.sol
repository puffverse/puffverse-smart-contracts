// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interfaces/IMintableERC721V3.sol';
import '../core/SafeOwnable.sol';
import '../core/TimeCore.sol';

contract NFTShop is SafeOwnable, TimeCore {
    using SafeERC20 for IERC20;

    event ItemChanged(uint id, IERC20 paymentToken, uint cost, IMintableERC721V3 receiveNFT, uint receiveNum, bool available);
    event ReceiverChanged(address oldReceiver, address newReceiver);
    event NftSupplyChanged(IMintableERC721V3 nft, uint oldSupply, uint newSupply);
    event Buy(uint id, address user, IERC20 paymentToken, uint cost, IMintableERC721V3 receiveNFT, uint[] nftIds, uint timestamp);

    struct Item {
        uint id;
        IERC20 paymentToken;
        uint cost;
        IMintableERC721V3 receiveNFT;
        uint receiveNum;
        bool available;
    }

    IERC20 immutable public WETH;
    Item[] public items;
    address payable public receiver;
    mapping(IMintableERC721V3 => uint) public nftSupply;
    mapping(IMintableERC721V3 => uint) public nftSelled;
    mapping(address => mapping(IMintableERC721V3 => uint)) public userBuyed;

    constructor(IERC20 _WETH, address payable _receiver) {
        WETH = _WETH;
        require(_receiver != address(0), "illegal receiver");
        emit ReceiverChanged(receiver, _receiver);
        receiver = _receiver;
    }

    function addItem(IERC20 _paymentToken, uint _cost, IMintableERC721V3 _receiveNFT, uint _receiveNum) internal {
        require(address(_paymentToken) != address(0) && address(_receiveNFT) != address(0), "illegal token");
        items.push(Item({
            id: items.length,
            paymentToken: _paymentToken,
            cost: _cost,
            receiveNFT: _receiveNFT,
            receiveNum: _receiveNum,
            available: true
        }));
        unchecked {
            emit ItemChanged(items.length - 1, _paymentToken, _cost, _receiveNFT, _receiveNum, true);
        }
    }

    function addItems(IERC20[] memory _paymentTokens, uint[] memory _costs, IMintableERC721V3[] memory _receiveNFTs, uint[] memory _receiveNums) external onlyOwner {
        require(_paymentTokens.length == _costs.length && _costs.length == _receiveNFTs.length && _receiveNFTs.length == _receiveNums.length, "illegallength"); 
        unchecked {
            for (uint i = 0; i < _paymentTokens.length; i ++) {
                addItem(_paymentTokens[i], _costs[i], _receiveNFTs[i], _receiveNums[i]);
            }
        }
    }

    function disableItems(uint[] memory _ids) external onlyOwner {
        unchecked {
            for (uint i = 0; i < _ids.length; i ++) {
                require(_ids[i] < items.length, "illegal id");
                Item storage item = items[_ids[i]];
                item.available = false;
                emit ItemChanged(item.id, item.paymentToken, item.cost, item.receiveNFT, item.receiveNum, item.available);
            }
        }
    }

    function enableItems(uint[] memory _ids) external onlyOwner {
        unchecked {
            for (uint i = 0; i < _ids.length; i ++) {
                require(_ids[i] < items.length, "illegal id");
                Item storage item = items[_ids[i]];
                item.available = true;
                emit ItemChanged(item.id, item.paymentToken, item.cost, item.receiveNFT, item.receiveNum, item.available);
            }
        }
    }

    function changeItem(uint _id, uint _cost, uint _receiveNum, bool _available) internal {
        require(_id < items.length, "illegal id");
        Item storage item = items[_id];
        item.cost = _cost;
        item.receiveNum = _receiveNum;
        item.available = _available;
        emit ItemChanged(_id, item.paymentToken, item.cost, item.receiveNFT, item.receiveNum, item.available);
    }

    function changeItems(Item[] memory _items) external onlyOwner {
        for (uint i = 0; i < _items.length; i ++) {
            changeItem(_items[i].id, _items[i].cost, _items[i].receiveNum, _items[i].available);
        }
    }

    function changeReceiver(address payable _receiver) external onlyOwner {
        require(_receiver != address(0), "illegal receiver");
        emit ReceiverChanged(receiver, _receiver);
        receiver = _receiver;
    }

    function changeSupply(IMintableERC721V3 _nft, uint _num) external onlyOwner {
        require(_num >= nftSelled[_nft], "already executed");
        emit NftSupplyChanged(_nft, nftSupply[_nft], _num);
        nftSupply[_nft] = _num;
    }

    function buy(uint _id, uint _cost, uint _receiveNum) external payable RightTime {
        require(_id < items.length, "illegal id");
        Item memory item = items[_id];
        require(item.available, "item not exist");
        require(item.cost == _cost && item.receiveNum == _receiveNum, "item changed");
        require(nftSelled[item.receiveNFT] + item.receiveNum <= nftSupply[item.receiveNFT], "already executed");
        if (item.paymentToken == WETH) {
            require(_cost == msg.value, "illegal cost");
            receiver.transfer(_cost);
        } else {
            item.paymentToken.safeTransferFrom(msg.sender, receiver, _cost);
        }
        uint currentSupply = item.receiveNFT.totalSupply();
        item.receiveNFT.mint(msg.sender, item.receiveNum);
        nftSelled[item.receiveNFT] += item.receiveNum;
        userBuyed[msg.sender][item.receiveNFT] += item.receiveNum;
        uint[] memory nftIds = new uint[](item.receiveNum);
        for (uint i = 0; i < item.receiveNum; i ++) {
            nftIds[i] = currentSupply + i + 1;
        }
        emit Buy(_id, msg.sender, item.paymentToken, item.cost, item.receiveNFT, nftIds, block.timestamp);
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
                itemList[currentIndex].paymentToken = items[i].paymentToken;
                itemList[currentIndex].cost = items[i].cost;
                itemList[currentIndex].receiveNFT = items[i].receiveNFT;
                itemList[currentIndex].receiveNum = items[i].receiveNum;
                itemList[currentIndex].available = items[i].available;
                unchecked {
                    currentIndex += 1;
                }
            }
        }
    }
}
