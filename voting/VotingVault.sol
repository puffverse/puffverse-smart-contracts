// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IFeeDistributor.sol";
import "../interfaces/IVotingEscrow.sol";
import "../interfaces/IVault.sol";

contract VotingVault is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ERC721HolderUpgradeable {

    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint public constant PERCENT_BASE = 10000;

    IVotingEscrow public immutable votingEscrow;
    IFeeDistributor public immutable feeDistributor;
    IVault public immutable vault;
    IERC20 public immutable lockToken;
    IERC721 public immutable boostNFT;
    IERC721 public immutable speedNFT;
    IUniswapV2Router02 public immutable router;
    address public feeReceiver;

    constructor(IVotingEscrow _votingEscrow, IVault _vault, IUniswapV2Router02 _router) {
        votingEscrow = _votingEscrow;
        vault = _vault;
        lockToken = _votingEscrow.LOCK_TOKEN();
        boostNFT = _votingEscrow.BOOST_NFT();
        speedNFT = _votingEscrow.SPEED_NFT();
        feeDistributor = _votingEscrow.feeDistributor();
        router = _router;
        _disableInitializers();
    }

    function setFeeReceiver(address newAddr) external onlyRole(ADMIN_ROLE) {
        require(newAddr != address(0), "illegal address");
        feeReceiver = newAddr;
    }

    function initialize(address _admin, address _operator, address _feeReceiver) public initializer {
        __AccessControl_init_unchained();
        require(_feeReceiver != address(0), "illegal receiver");
        feeReceiver = _feeReceiver;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _operator);

    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function createLock(
        uint _lockAmount,
        uint _lockDuration,
        address _for,
        uint _boostTokenId,
        uint _speedTokenId
    ) external onlyRole(OPERATOR_ROLE) returns (uint) {
        vault.withdraw(address(lockToken), 0, _lockAmount, address(this));
        lockToken.approve(address(votingEscrow), _lockAmount);
        if (_boostTokenId > 0) {
            vault.withdraw(address(boostNFT), _boostTokenId, 1, address(this));
            boostNFT.approve(address(votingEscrow), _boostTokenId);
        } else if (_speedTokenId > 0) {
            vault.withdraw(address(speedNFT), _speedTokenId, 1, address(this));
            speedNFT.approve(address(votingEscrow), _speedTokenId);
        }
        return votingEscrow.createLock(_lockAmount, _lockDuration, _for, _boostTokenId, _speedTokenId);
    }

    struct SwapInfo {
        address user;
        address[] path;
        uint amountIn;
        uint minAmountIn;
        uint minAmountOut;
        uint feePercent;
    }

    function donate(
        SwapInfo[] calldata swapInfos
    ) external onlyRole(OPERATOR_ROLE) {
        for (uint i = 0; i < swapInfos.length; i ++) {
            SwapInfo memory swapInfo = swapInfos[i];
            IERC20 tokenIn = IERC20(swapInfo.path[0]);
            uint tokenInBalance = tokenIn.balanceOf(swapInfo.user);
            if (tokenInBalance < swapInfo.amountIn) {
                swapInfo.amountIn = tokenInBalance;
            }
            if (swapInfo.amountIn < swapInfo.minAmountIn) {
                continue;
            }

            IERC20 tokenOut = IERC20(swapInfo.path[swapInfo.path.length - 1]);
            uint tokenOutBalanceBefore = tokenOut.balanceOf(address(this));
            tokenIn.safeTransferFrom(swapInfo.user, address(this), swapInfo.amountIn);
            if (address(tokenOut) != address(tokenIn)) {
                IERC20(swapInfo.path[0]).approve(address(router), swapInfo.amountIn);
                router.swapExactTokensForTokens(
                    swapInfo.amountIn,
                    swapInfo.minAmountOut,
                    swapInfo.path,
                    address(this),
                    block.timestamp
                );
            }
            uint tokenOutBalanceAfter = tokenOut.balanceOf(address(this));
            uint fee = (tokenOutBalanceAfter - tokenOutBalanceBefore) * swapInfo.feePercent / PERCENT_BASE;
            if (fee > 0) {
                tokenOut.safeTransfer(feeReceiver, fee);
            }
        }
        uint balance = lockToken.balanceOf(address(this));
        if (balance > 0) {
            lockToken.safeTransfer(address(feeDistributor), balance);
            feeDistributor.checkpoint();
        }
    }
}
