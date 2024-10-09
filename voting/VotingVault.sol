// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVotingEscrow.sol";
import "../interfaces/IVault.sol";

contract VotingVault is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ERC721HolderUpgradeable {

    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IVotingEscrow public immutable votingEscrow;
    IVault public immutable vault;
    IERC20 public immutable lockToken;
    IERC721 public immutable boostNFT;

    constructor(IVotingEscrow _votingEscrow, IVault _vault) {
        votingEscrow = _votingEscrow;
        vault = _vault;
        lockToken = _votingEscrow.LOCK_TOKEN();
        boostNFT = _votingEscrow.BOOST_NFT();
        _disableInitializers();
    }

    function initialize(address _admin, address _operator) public initializer {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _operator);

    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function createLock(
        uint _lockAmount, 
        uint _lockDuration, 
        address _for, 
        uint _boostTokenId
    ) external onlyRole(OPERATOR_ROLE) returns (uint) {
        vault.withdraw(address(lockToken), 0, _lockAmount, address(this));
        lockToken.approve(address(votingEscrow), _lockAmount);
        if (_boostTokenId > 0) {
            vault.withdraw(address(boostNFT), _boostTokenId, 1, address(this));
            boostNFT.approve(address(votingEscrow), _boostTokenId);
        }
        return votingEscrow.createLock(_lockAmount, _lockDuration, _for, _boostTokenId);
    }
}
