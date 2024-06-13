// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '../interfaces/IMintableBurnableERC721V2.sol';
import '../core/SafeOwnable.sol';
import '../core/Mintable.sol';
import '../core/Burnable.sol';
import '../core/NFTCoreV5.sol';
import '../interfaces/INFTLaunchpad.sol';

contract SpaceNFT is NFTCoreV5 {

    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _uri
    ) NFTCoreV5(_name, _symbol, _uri, 2020) {
    }

    function burn(address _user, uint256 _tokenId) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have burn role to burn");
        burnInternal(_user, _tokenId);
    }

    function mint(address to) public override returns (uint256 _tokenId) {
        require(totalSupply() < MAX_SUPPLY, "executed");
        return super.mint(to);
    }

    function mintLaunchpad(address to, uint256 quantity, bytes calldata /* extraData */ )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256[] memory tokenIds, uint256[] memory amounts)
    {
        tokenIds = new uint256[](quantity);
        amounts = new uint256[](quantity);
        for (uint256 i; i < quantity; ++i) {
            tokenIds[i] = _mintFor(to);
            amounts[i] = 1;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(INFTLaunchpad).interfaceId || super.supportsInterface(interfaceId);
    }
}
