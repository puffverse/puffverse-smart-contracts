// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '../interfaces/IERC721CoreV2.sol';
import './SafeOwnableInterface.sol';
import '../axieinfinity/ERC721Common.sol';

abstract contract NFTCoreV5 is ERC721Common {

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    uint public immutable MAX_SUPPLY;

    constructor(string memory _name, string memory _symbol, string memory _uri, uint _maxSupply) ERC721Common(_name, _symbol, _uri) {
        MAX_SUPPLY = _maxSupply;
        _setupRole(BURNER_ROLE, _msgSender());
    }

    function burnInternal(address _user, uint256 _tokenId) internal {
        require(ownerOf(_tokenId) == _user, "illegal owner");
        require(_isApprovedOrOwner(msg.sender, _tokenId), "caller is not owner nor approved");
        _transfer(_user, BURN_ADDRESS, _tokenId);
    }
}
