// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;


import '@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract MockVault is Initializable, AccessControlEnumerableUpgradeable, UUPSUpgradeable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    event Withdraw(address user, uint timestamp, TokenType tokenType, address token, uint tokenId, uint amount);

    enum TokenType {
        NONE,
        NATIVE,
        ERC20,
        ERC721,
        ERC1155
    }
    
    mapping(address => TokenType) public supportTokens;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address[] memory _operators) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        for (uint i = 0; i < _operators.length; i ++) {
            _grantRole(OPERATOR_ROLE, _operators[i]);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Holder, AccessControlEnumerableUpgradeable) returns (bool) {
        return ERC1155Holder.supportsInterface(interfaceId) || AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
    }

    function withdraw(address _token, uint _tokenId, uint _amount, address _recipient) public onlyRole(OPERATOR_ROLE) {
        TokenType tokenType = supportTokens[_token];
        if (tokenType == TokenType.NATIVE) {
            require(_tokenId == 0, "illegal token or tokenId");
            payable(_recipient).transfer(_amount);
        } else if (tokenType == TokenType.ERC20) {
            require(_tokenId == 0, "illegal token or tokenId");
            IERC20(_token).safeTransfer(_recipient, _amount);
        } else if (tokenType == TokenType.ERC721) {
            require(_amount == 1, "illegal token or amount");
            IERC721(_token).safeTransferFrom(address(this), _recipient, _tokenId, new bytes(0));
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(_token).safeTransferFrom(address(this), _recipient, _tokenId, _amount, new bytes(0));
        } else {
            revert("illegal token type");
        }
        emit Withdraw(_recipient, block.timestamp, tokenType, _token, _tokenId, _amount);
    }

    function setSupportToken(address _token, TokenType _type) external onlyRole(ADMIN_ROLE) {
        supportTokens[_token] = _type;
    }
}
