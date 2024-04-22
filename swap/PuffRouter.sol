// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '../core/SafeOwnable.sol';
import '../interfaces/IWETH.sol';

interface ISwapPair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
}

contract PuffRouter is SafeOwnable, Pausable {
    using SafeERC20 for IERC20;

    event NewSwapFee(uint oldValue, uint newValue);
    event NewSwapReceiver(address oldReceiver, address newReceiver);
    
    address public immutable factory;
    bytes32 public immutable pairInitCodeHash;
    uint256 public immutable fee;
    uint256 public immutable feeBase;
    address public immutable WETH;
    uint public swapFee;
    uint public constant MAX_SWAP_FEE = 5000;
    uint public constant PERCENT_BASE = 1e6;
    address public swapFeeReceiver;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'PuffRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH, uint _swapFee, address _swapFeeReceiver, bytes32 _pairInitCodeHash, uint _fee, uint _feeBase) {
        factory = _factory;
        WETH = _WETH;
        _setSwapFee(_swapFee);
        _setSwapFeeReceiver(_swapFeeReceiver);
        pairInitCodeHash = _pairInitCodeHash;
        fee = _fee;
        feeBase = _feeBase;
    }

    receive() external payable {
        assert(msg.sender == WETH); 
    }

    function pause() internal virtual whenNotPaused {
        _pause();
    }

    function unpause() internal virtual whenPaused {
        _unpause();
    }

    function _setSwapFee(uint _swapFee) internal {
        require(_swapFee <= MAX_SWAP_FEE, "illegal swapFee");
        emit NewSwapFee(swapFee, _swapFee);
        swapFee = _swapFee;
    }

    function setSwapFee(uint _swapFee) public onlyOwner {
        _setSwapFee(_swapFee);
    }

    function _setSwapFeeReceiver(address _swapFeeReceiver) internal {
        require(_swapFeeReceiver != address(0), "illegal receiver");
        emit NewSwapReceiver(swapFeeReceiver, _swapFeeReceiver);
        swapFeeReceiver = _swapFeeReceiver;
    }

    function setSwapFeeReceiver(address _swapFeeReceiver) public onlyOwner {
        _setSwapFeeReceiver(_swapFeeReceiver);
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZERO_ADDRESS');
    }

    function pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                pairInitCodeHash
            )))));
    }

    function getReserves(address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = ISwapPair(pairFor(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal view returns (uint amountOut) {
        require(amountIn > 0, 'INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn * (feeBase - fee);
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * feeBase + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal view returns (uint amountIn) {
        require(amountOut > 0, 'INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn * amountOut * feeBase;
        uint denominator = (reserveOut - amountOut) * (feeBase - fee);
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
            ISwapPair(pairFor(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        uint payFee = amountIn * swapFee / PERCENT_BASE;
        IERC20(path[0]).safeTransferFrom(
            msg.sender, swapFeeReceiver, payFee
        );
        amountIn -= payFee;
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        IERC20(path[0]).safeTransferFrom(
            msg.sender, pairFor(path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'EXCESSIVE_INPUT_AMOUNT');
        uint payFee = amounts[0] * swapFee / (PERCENT_BASE - swapFee);
        IERC20(path[0]).safeTransferFrom(
            msg.sender, swapFeeReceiver, payFee
        );
        IERC20(path[0]).safeTransferFrom(
            msg.sender, pairFor(path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'INVALID_PATH');
        uint payFee = msg.value * swapFee / PERCENT_BASE;
        uint amountIn = msg.value - payFee;
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: msg.value}();
        IERC20(WETH).safeTransfer(swapFeeReceiver, payFee);
        IERC20(WETH).safeTransfer(pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address payable to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'INVALID_PATH');
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'EXCESSIVE_INPUT_AMOUNT');
        uint payFee = amounts[0] * swapFee / (PERCENT_BASE - swapFee);
        IERC20(path[0]).safeTransferFrom(
            msg.sender, swapFeeReceiver, payFee
        );
        IERC20(path[0]).safeTransferFrom(
            msg.sender, pairFor(path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        to.transfer(amounts[amounts.length-1]);
    }

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address payable to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'INVALID_PATH');
        uint payFee = amountIn * swapFee / PERCENT_BASE;
        IERC20(path[0]).safeTransferFrom(
            msg.sender, swapFeeReceiver, payFee
        );
        amountIn -= payFee;
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        IERC20(path[0]).safeTransferFrom(
            msg.sender, pairFor(path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        to.transfer(amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'INVALID_PATH');
        amounts = getAmountsIn(amountOut, path);
        uint payFee = amounts[0] * swapFee / (PERCENT_BASE - swapFee);
        require(amounts[0] + payFee <= msg.value, 'EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0] + payFee}();
        IERC20(WETH).safeTransfer(swapFeeReceiver, payFee);
        IERC20(WETH).safeTransfer(pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
        if (msg.value > amounts[0] + payFee) payable(msg.sender).transfer(msg.value - amounts[0] - payFee);
    }
}
