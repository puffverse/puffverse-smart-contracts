// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './SafeOwnableInterface.sol';
import '../interfaces/IWETH.sol';

abstract contract TransferCore is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IWETH public immutable WETH;

    constructor(IWETH _weth) {
        require(address(_weth) != address(0), "illegal weth");
        WETH = _weth;
    }

    function tokenTransferFrom(IERC20 _token, address _from, address _to, uint _amount) internal nonReentrant {
        if (address(_token) == address(WETH)) {
            if (_to == address(this)) {
                require(msg.value >= _amount, "illegal amount");
                WETH.deposit{value: _amount}();
            } else if (_from == address(this)) {
                WETH.withdraw(_amount);
                payable(_to).transfer(_amount);
            } else {
                payable(_to).transfer(_amount);
            }
        } else {
            _token.safeTransferFrom(_from, _to, _amount);
        }
    }

    function tokenBalance(IERC20 _token, address _user) internal view returns (uint) {
        if (address(_token) == address(WETH)) {
            return _user.balance;
        } else {
            return _token.balanceOf(_user);
        }
    }

}
