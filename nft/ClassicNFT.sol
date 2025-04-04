// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../interfaces/IMintableBurnableERC721V2.sol';
import '../core/SafeOwnable.sol';
import '../core/Mintable.sol';
import '../core/Burnable.sol';
import '../core/NFTCoreV5.sol';

contract ClassicNFT is NFTCoreV5 {

    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) NFTCoreV5(_name, _symbol, _uri, type(uint256).max) {
    }

    function burn(address _user, uint256 _tokenId) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have burn role to burn");
        burnInternal(_user, _tokenId);
    }

    function mint(address to) public override returns (uint256 _tokenId) {
        require(totalSupply() < MAX_SUPPLY, "executed");
        return super.mint(to);
    }
}
