// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../core/NFTCoreV5.sol';

contract GeneralNFT is NFTCoreV5 {

    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) NFTCoreV5(_name, _symbol, _uri, type(uint).max) {
    }

    function burn(address _user, uint256 _tokenId) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have burn role to burn");
        burnInternal(_user, _tokenId);
    }

    function mint(address to) public override returns (uint256) {
        require(totalSupply() < MAX_SUPPLY, "executed");
        return super.mint(to);
    }

    function mintById(address _to, uint _tokenId) external {
        _mint(_to, _tokenId);
    }

    function exists(uint _tokenId) external view returns(bool) {
        return _exists(_tokenId);        
    }
}
