// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../core/SafeOwnable.sol';
import '../core/VerifierV2.sol';

contract Vault is SafeOwnable, Initializable, VerifierV2, IERC721Receiver, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event SupportTokenChanged(address token, TokenType tokenType);
    event Deposit(uint orderId, address user, uint timestamp, TokenType tokenType, address token, uint tokenId, uint amount, uint totalAmount);
    event Withdraw(uint orderId, address user, uint timestamp, TokenType tokenType, address token, uint tokenId, uint amount, uint totalAmount);
    event RecoverWrongToken(TokenType tokenType, address token, uint tokenId, uint amount, address receiver);

    enum TokenType {
        NONE,
        NATIVE,
        ERC20,
        ERC721,
        ERC1155
    }
    
    uint orderId = 1;
    mapping(bytes32 => bool) public hashes;
    mapping(address => TokenType) public supportTokens;

    //AssetKey = keccak256(abi.encodePacked(user, token, tokenId)) and for NATIVE and ERC20 the tokenId is alway 0
    //TokenKey = keccak256(abi.encodePacked(token, tokenId)) and for NATIVE and ERC20 the tokenId is alway 0;
    mapping(bytes32 => uint) public userOrderId;        //every time the user deposit or withdraw, a new orderId will produced, and the old on will be useless
    mapping(bytes32 => uint) public userBalance;        //the balance of a asset user deposited into the vault
    mapping(bytes32 => uint) public tokenBalance;       //the total balance of a asset that all user deposited into the vault

    function initialize(address _owner, address _verifier) external initializer {
        _transferOwnership(_owner);
        _setVerifier(_verifier);
    }

    function setSupportToken(address _token, TokenType _type) external onlyOwner {
        supportTokens[_token] = _type;
        emit SupportTokenChanged(_token, _type);
    }

    struct DepositParam {
        address token;
        uint tokenId;
        uint amount;
    }

    function AssetKey(address user, DepositParam memory param) internal pure returns (bytes32, bytes32) {
        return (keccak256(abi.encodePacked(user, param.token, param.tokenId)), keccak256(abi.encodePacked(param.token, param.tokenId)));
    }

    function deposit(DepositParam memory param) external payable nonReentrant {
        TokenType tokenType = supportTokens[param.token];
        (bytes32 assetKey, bytes32 tokenKey) = AssetKey(msg.sender, param);
        if (tokenType == TokenType.NATIVE) {
            require(param.tokenId == 0, "illegal token or tokenId");
            require(msg.value == param.amount, "illegal amount");
            userBalance[assetKey] += param.amount;
        } else if (tokenType == TokenType.ERC20) {
            require(param.tokenId == 0, "illegal token or tokenId");
            IERC20(param.token).safeTransferFrom(msg.sender, address(this), param.amount);
            userBalance[assetKey] += param.amount;
        } else if (tokenType == TokenType.ERC721) {
            require(param.amount == 1, "illegal token or amount");
            IERC721(param.token).safeTransferFrom(msg.sender, address(this), param.tokenId, new bytes(0));
            userBalance[assetKey] = param.amount;
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(param.token).safeTransferFrom(msg.sender, address(this), param.tokenId, param.amount, new bytes(0));
            userBalance[assetKey] += param.amount;
        } else {
            revert("illegal token type");
        }
        tokenBalance[tokenKey] += param.amount;
        userOrderId[assetKey] = orderId;
        emit Deposit(orderId ++, msg.sender, block.timestamp, tokenType, param.token, param.tokenId, param.amount, userBalance[assetKey]);
    }

    struct WithdrawParam {
        uint id;
        address token;
        uint tokenId;
        uint amount;
        uint totalAmount;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function AssetKey(address user, WithdrawParam memory param) internal pure returns (bytes32, bytes32) {
        return (keccak256(abi.encodePacked(user, param.token, param.tokenId)), keccak256(abi.encodePacked(param.token, param.tokenId)));
    }

    function withdraw(WithdrawParam memory param) external nonReentrant {
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(
            address(this), param.id, msg.sender, param.token, param.tokenId, param.amount, param.totalAmount
        ))));
        address signer = ecrecover(hash, param.v, param.r, param.s);
        require(!hashes[hash] && signer != address(0) && signer == verifier, "signature failed");
        hashes[hash] = true;
        TokenType tokenType = supportTokens[param.token];
        (bytes32 assetKey, bytes32 tokenKey) = AssetKey(msg.sender, param);
        require(userOrderId[assetKey] == param.id, "illegal id");
        uint currentBalance = userBalance[assetKey];
        if (tokenType == TokenType.NATIVE) {
            require(param.tokenId == 0, "illegal token or tokenId");
            if (param.totalAmount > currentBalance) {
                require(param.totalAmount - currentBalance <= address(this).balance - tokenBalance[tokenKey], "illegal totalAmount");
            }
            payable(msg.sender).transfer(param.amount);
            userBalance[assetKey] = param.totalAmount - param.amount;
            if (param.totalAmount > param.amount) {
                userOrderId[assetKey] = orderId;
                emit Deposit(orderId ++, msg.sender, block.timestamp, tokenType, param.token, param.tokenId, 0, param.totalAmount - param.amount);
            } else {
                delete userOrderId[assetKey];
                delete userBalance[assetKey];
            }
        } else if (tokenType == TokenType.ERC20) {
            require(param.tokenId == 0, "illegal token or tokenId");
            if (param.totalAmount > currentBalance) {
                require(param.totalAmount - currentBalance <= IERC20(param.token).balanceOf(address(this)) - tokenBalance[tokenKey], "illegal totalAmount");
            }
            IERC20(param.token).safeTransfer(msg.sender, param.amount);
            userBalance[assetKey] = param.totalAmount - param.amount;
            if (param.totalAmount > param.amount) {
                userOrderId[assetKey] = orderId;
                emit Deposit(orderId ++, msg.sender, block.timestamp, tokenType, param.token, param.tokenId, 0, param.totalAmount - param.amount);
            } else {
                delete userOrderId[assetKey];
                delete userBalance[assetKey];
            }
        } else if (tokenType == TokenType.ERC721) {
            require(param.amount == 1 && param.totalAmount == 1, "illegal token or amount");
            if (currentBalance == 0) {
                require(IERC721(param.token).ownerOf(param.tokenId) == address(this) && tokenBalance[tokenKey] == 0, "illeagl totalAmount"); 
            }
            IERC721(param.token).safeTransferFrom(address(this), msg.sender, param.tokenId, new bytes(0));
            delete userOrderId[assetKey];
            delete userBalance[assetKey];
        } else if (tokenType == TokenType.ERC1155) {
            if (param.totalAmount > currentBalance) {
                require(param.totalAmount - currentBalance <= IERC1155(param.token).balanceOf(address(this), param.tokenId) - tokenBalance[tokenKey], "illeagl totalAmount");
            }
            IERC1155(param.token).safeTransferFrom(address(this), msg.sender, param.tokenId, param.amount, new bytes(0));
            userBalance[assetKey] = param.totalAmount - param.amount;
            if (param.totalAmount > param.amount) {
                userOrderId[assetKey] = orderId;
                emit Deposit(orderId ++, msg.sender, block.timestamp, tokenType, param.token, param.tokenId, 0, param.totalAmount - param.amount);
            } else {
                delete userOrderId[assetKey];
                delete userBalance[assetKey];
            }
        } else {
            revert("illegal token type");
        }
        if (param.totalAmount >= currentBalance) {
            tokenBalance[tokenKey] = tokenBalance[tokenKey] + (param.totalAmount - currentBalance) - param.amount;
        } else {
            tokenBalance[tokenKey] = tokenBalance[tokenKey] - (currentBalance - param.totalAmount) - param.amount;
        }
        emit Withdraw(param.id, msg.sender, block.timestamp, tokenType, param.token, param.tokenId, param.amount, param.totalAmount);
    }

    function AssetKey(address user, address token, uint tokenId) internal pure returns (bytes32, bytes32) {
        return (keccak256(abi.encodePacked(user, token, tokenId)), keccak256(abi.encodePacked(token, tokenId)));
    }

    function recoverWrongToken(TokenType tokenType, address token, uint tokenId, uint amount, address payable receiver) external onlyOwner {
        (, bytes32 tokenKey) = AssetKey(msg.sender, token, tokenId);
        if (tokenType == TokenType.NATIVE) {
            uint remain = address(this).balance - tokenBalance[tokenKey];
            require(remain >= amount, "illegal amount"); 
            receiver.transfer(amount);
        } else if (tokenType == TokenType.ERC20) {
            uint remain = IERC20(token).balanceOf(address(this)) - tokenBalance[tokenKey];
            require(remain >= amount, "illegal amount"); 
            IERC20(token).safeTransfer(receiver, amount);
        } else if (tokenType == TokenType.ERC721) {
            require(amount == 1 && tokenBalance[tokenKey] == 0, "illegal amount");
            IERC721(token).safeTransferFrom(address(this), receiver, tokenId, new bytes(0));
        } else if (tokenType == TokenType.ERC1155) {
            uint remain = IERC1155(token).balanceOf(address(this), tokenId) - tokenBalance[tokenKey];
            require(remain >= amount, "illegal amount");
            IERC1155(token).safeTransferFrom(address(this), receiver, tokenId, amount, new bytes(0));
        } else {
            revert("illegal token type");
        }
        emit RecoverWrongToken(tokenType, token, tokenId, amount, receiver);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override pure returns (bytes4) {
        if (false) {
            operator;
            from;
            tokenId;
            data;
        }
        return 0x150b7a02;
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override pure returns (bytes4) {
        if (false) {
            operator;
            from;
            id;
            value;
            data;
        }
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override pure returns (bytes4) {
        if (false) {
            operator;
            from;
            ids;
            values;
            data;
        }
        return 0xbc197c81;
    }

    function supportsInterface(bytes4 interfaceId) external override pure returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    receive() external payable {}
}
