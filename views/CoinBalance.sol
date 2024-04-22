// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract CoinBalance is Ownable {
    mapping(uint => address) public tokensMap;
    uint public tokensMapSize;

    function setTokens(address[]  memory _tokens) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            tokensMap[i] = _tokens[i];
        }
        tokensMapSize = _tokens.length;
    }

    function getTokensBalance(address _sender)
    public view returns
    (address[] memory tokens, uint[] memory decimal, uint[] memory balance){
        tokens = new address[](tokensMapSize);
        decimal = new uint[](tokensMapSize);
        balance = new uint[](tokensMapSize);
        for (uint i = 0; i < tokensMapSize; i++) {
            address _token = tokensMap[i];
            tokens[i] = _token;
            if (_token == address(0)) {
                balance[i] = _sender.balance;
                decimal[i] = 18;
            } else {
                balance[i] = IERC20(_token).balanceOf(_sender);
                decimal[i] = IERC20Metadata(_token).decimals();
            }
        }
        return (tokens,decimal,balance);
    }
}
