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

import '../interfaces/IMintableERC721V4.sol';
import '../core/SafeOwnable.sol';
import '../core/VerifierV2.sol';
import '../core/Operatable.sol';

contract VaultV2 is SafeOwnable, Operatable, Initializable, IERC721Receiver, IERC1155Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event SupportTokenChanged(address token, TokenType tokenType);
    event MintableNFTChanged(address token, bool available);
    event Deposit(address user, uint timestamp, TokenType tokenType, address token, uint tokenId, uint amount);
    event Withdraw(address user, uint timestamp, TokenType tokenType, address token, uint tokenId, uint amount);
    event RecoverWrongToken(TokenType tokenType, address token, uint tokenId, uint amount, address receiver);

    enum TokenType {
        NONE,
        NATIVE,
        ERC20,
        ERC721,
        ERC1155
    }
    
    mapping(address => TokenType) public supportTokens;
    mapping(address => bool) public mintableNFTs;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address[] memory _operators) external initializer {
        _transferOwnership(_owner);
        for (uint i = 0; i < _operators.length; i ++) {
            _addOperator(_operators[i]);
        }
    }

    function setSupportToken(address _token, TokenType _type) external onlyOwner {
        supportTokens[_token] = _type;
        emit SupportTokenChanged(_token, _type);
    }

    function setMintableNFT(address _token, bool _available) external onlyOwner {
        if (_available) {
            require(supportTokens[_token] == TokenType.ERC721, "not support token");
        }
        mintableNFTs[_token] = _available;
        emit MintableNFTChanged(_token, _available);
    }

    struct DepositParam {
        address token;
        uint tokenId;
        uint amount;
    }

    function deposit(DepositParam memory param) public payable nonReentrant {
        TokenType tokenType = supportTokens[param.token];
        if (tokenType == TokenType.NATIVE) {
            require(param.tokenId == 0, "illegal token or tokenId");
            require(msg.value >= param.amount, "illegal amount");
        } else if (tokenType == TokenType.ERC20) {
            require(param.tokenId == 0, "illegal token or tokenId");
            IERC20(param.token).safeTransferFrom(msg.sender, address(this), param.amount);
        } else if (tokenType == TokenType.ERC721) {
            require(param.amount == 1, "illegal token or amount");
            IERC721(param.token).safeTransferFrom(msg.sender, address(this), param.tokenId, new bytes(0));
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(param.token).safeTransferFrom(msg.sender, address(this), param.tokenId, param.amount, new bytes(0));
        } else {
            revert("illegal token type");
        }
        emit Deposit(msg.sender, block.timestamp, tokenType, param.token, param.tokenId, param.amount);
    }

    function depositAll(DepositParam[] memory param) external payable {
        uint totalValue = 0;
        for (uint i = 0; i < param.length; i ++) {
            if (supportTokens[param[i].token] == TokenType.NATIVE) {
                totalValue += param[i].amount;
            }
            deposit(param[i]);
        }
        require(msg.value == totalValue, "illegal value");
    }

    function withdraw(address _token, uint _tokenId, uint _amount, address _recipient) public onlyOperater nonReentrant {
        TokenType tokenType = supportTokens[_token];
        if (tokenType == TokenType.NATIVE) {
            require(_tokenId == 0, "illegal token or tokenId");
            payable(_recipient).transfer(_amount);
        } else if (tokenType == TokenType.ERC20) {
            require(_tokenId == 0, "illegal token or tokenId");
            IERC20(_token).safeTransfer(_recipient, _amount);
        } else if (tokenType == TokenType.ERC721) {
            require(_amount == 1, "illegal token or amount");
            if (mintableNFTs[_token] && !IMintableERC721V4(_token).exists(_tokenId)) {
                IMintableERC721V4(_token).mintById(_recipient, _tokenId);
            } else {
                IERC721(_token).safeTransferFrom(address(this), _recipient, _tokenId, new bytes(0));
            }
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(_token).safeTransferFrom(address(this), _recipient, _tokenId, _amount, new bytes(0));
        } else {
            revert("illegal token type");
        }
        emit Withdraw(_recipient, block.timestamp, tokenType, _token, _tokenId, _amount);
    }

    function withdrawAll(address[] memory _tokens, uint[] memory _tokenIds, uint[] memory _amounts, address[] memory _recipients) external onlyOperater {
        require(_tokens.length == _tokenIds.length && _tokenIds.length == _amounts.length && _amounts.length == _recipients.length, "illegal length");
        for (uint i = 0; i < _tokens.length; i ++) {
            withdraw(_tokens[i], _tokenIds[i], _amounts[i], _recipients[i]);
        }
    }

    function recoverWrongToken(TokenType tokenType, address token, uint tokenId, uint amount, address payable receiver) external onlyOwner {
        if (tokenType == TokenType.NATIVE) {
            receiver.transfer(amount);
        } else if (tokenType == TokenType.ERC20) {
            IERC20(token).safeTransfer(receiver, amount);
        } else if (tokenType == TokenType.ERC721) {
            IERC721(token).safeTransferFrom(address(this), receiver, tokenId, new bytes(0));
        } else if (tokenType == TokenType.ERC1155) {
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
