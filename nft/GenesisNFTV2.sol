// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../core/SafeOwnable.sol';
import '../core/NFTCoreV3.sol';
import '../core/Mintable.sol';
import '../core/Burnable.sol';

contract GenesisNFTV2 is SafeOwnable, NFTCoreV3, Mintable, Burnable {

    uint public constant MINT_START_ID = 2501;
    uint public mintId = MINT_START_ID;
    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) NFTCoreV3(_name, _symbol, _uri, 2500) Mintable(new address[](0), false) Burnable(new address[](0), false) {
    }

    function mint(address _to, uint _num) external onlyMinter {
        for (uint i = 0; i < _num; i ++) {
            mintByIdInternal(_to, mintId + i);
        }
        mintId += _num;
    }

    function mintById(address _to, uint _tokenId) external onlyMinter {
        require(_tokenId < MINT_START_ID, "illeagl _tokenId");
        mintByIdInternal(_to, _tokenId);
    }

    function burn(address _user, uint256 _tokenId) external onlyBurner {
        burnInternal(_user, _tokenId); 
    }

    function exists(uint _tokenId) external view returns(bool) {
        return _exists(_tokenId);
    }
}
