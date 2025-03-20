// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/IVotingEscrow.sol";
import "../interfaces/IFeeDistributor.sol";

contract FeeDistributor is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    using SafeERC20 for IERC20;

    event CheckpointToken(
        uint time,
        uint tokens
    );

    event Claimed (
        uint tokenId,
        uint amount,
        uint claim_epoch,
        uint max_epoch
    );

    uint constant WEEK = 7 * 86400;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IVotingEscrow  public immutable votingEscrow;
    IERC20 public immutable lockToken;

    uint public startTime;
    uint public lastTokenTime;
    uint public timeCursor;
    uint public tokenLastBalance;
    uint public totalClaimed;
    mapping(uint => uint) public tokensPerWeek;
    mapping(uint => uint) public veSupply;
    mapping(uint => uint) public timeCursorOf;
    mapping(uint => uint) public nftEpochOf;
    mapping(uint => mapping(uint => uint)) public claimed;
    mapping(uint => uint) public tokensTotalWeek;

    constructor(IVotingEscrow _votingEscrow) {
        votingEscrow = _votingEscrow;
        lockToken = _votingEscrow.LOCK_TOKEN();
        _disableInitializers();
    }

    function initialize(address _admin) public initializer {
        __AccessControl_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        uint currentWeek = block.timestamp / WEEK * WEEK;
        startTime = currentWeek;
        lastTokenTime = currentWeek;
        timeCursor = currentWeek;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function claim(uint tokenId) external nonReentrant whenNotPaused returns (uint) {
        require(votingEscrow.nftOwner(tokenId) == msg.sender, "Not owner");
        return _claimFor(tokenId, false);
    }

    function claimVE(uint tokenId) external nonReentrant whenNotPaused {
        require(address(votingEscrow) == msg.sender, "Not votingEscrow");
        _claimFor(tokenId, true);
    }

    function _claimFor(uint tokenId, bool isVE) internal returns (uint) {
        if (block.timestamp >= timeCursor) _totalSupplyCheckpoint();
        uint currentWeek = lastTokenTime / WEEK * WEEK;
        uint amount = _claim(tokenId, currentWeek);
        if (amount != 0) {
            if (isVE) {
                lockToken.safeTransfer(votingEscrow.nftOwner(tokenId), amount);
            } else {
                lockToken.safeTransfer(msg.sender, amount);
            }
            tokenLastBalance -= amount;
            totalClaimed += amount;
        }
        return amount;
    }

    function claimMany(uint[] calldata tokenIds) external nonReentrant whenNotPaused returns (bool) {
        if (block.timestamp >= timeCursor) _totalSupplyCheckpoint();
        uint currentWeek = lastTokenTime / WEEK * WEEK;
        uint total = 0;

        for (uint i = 0; i < tokenIds.length; i++) {
            uint tokenId = tokenIds[i];
            require(votingEscrow.nftOwner(tokenId) == msg.sender, "Not owner");
            total += _claim(tokenId, currentWeek);
        }
        if (total > 0) {
            lockToken.safeTransfer(msg.sender, total);
            tokenLastBalance -= total;
            totalClaimed += total;
        }
        return true;
    }

    function claimable(uint tokenId) external view returns (uint) {
        uint currentWeek = lastTokenTime / WEEK * WEEK;
        return _claimable(tokenId, currentWeek);
    }

    function claimableNext(uint tokenId) external view returns (uint) {
        uint currentWeek = lastTokenTime / WEEK * WEEK + WEEK;
        return _claimable(tokenId, currentWeek);
    }

    function veAt(uint tokenId, uint timestamp) external view returns (uint) {
        uint maxUserEpoch = votingEscrow.nftPointEpoch(tokenId);
        uint epoch = _findTimestampNftEpoch(tokenId, timestamp, maxUserEpoch);
        IVotingEscrow.Point memory pt = IVotingEscrow.Point(0, 0, 0, 0);
        (pt.bias, pt.slope, pt.ts, pt.blk) = votingEscrow.nftPointHistory(tokenId, epoch);
        int256 power = int256(pt.bias - pt.slope * (int128(int256(timestamp - pt.ts))));
        if (power < 0) {
            return 0;
        }
        return uint(power);
    }

    function checkpoint() external {
        _tokenCheckpoint();
        _totalSupplyCheckpoint();
    }

    function getDonateInfo(uint timestamp) external view returns (uint, uint) {
        uint week = timestamp / WEEK * WEEK;
        return (votingEscrow.totalPowerAt(week), tokensPerWeek[week]);
    }


    function withdrawReward(address _token, uint _amount) external onlyRole(ADMIN_ROLE) {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function _findTimestampEpoch(uint timestamp) internal view returns (uint) {
        uint min = 0;
        uint max = votingEscrow.epoch();
        for (uint i = 0; i < 128; i++) {
            if (min >= max) break;
            uint mid = (min + max + 2) / 2;
            IVotingEscrow.Point memory pt = IVotingEscrow.Point(0, 0, 0, 0);
            (pt.bias, pt.slope, pt.ts, pt.blk) = votingEscrow.pointHistory(mid);
            if (pt.ts <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    function _findTimestampNftEpoch(uint tokenId, uint timestamp, uint maxUserEpoch) internal view returns (uint) {
        uint min = 0;
        uint max = maxUserEpoch;
        for (uint i = 0; i < 128; i++) {
            if (min >= max) break;
            uint mid = (min + max + 2) / 2;
            IVotingEscrow.Point memory pt = IVotingEscrow.Point(0, 0, 0, 0);
            (pt.bias, pt.slope, pt.ts, pt.blk) = votingEscrow.nftPointHistory(tokenId, mid);
            if (pt.ts <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    function _claim(uint tokenId, uint time) internal returns (uint) {
        uint nftEpoch = 0;
        uint toDistribute = 0;

        uint maxNftEpoch = votingEscrow.nftPointEpoch(tokenId);
        uint currentTime = startTime;

        // No lock = no fees
        if (maxNftEpoch == 0) return 0;

        uint currentWeekCursor = timeCursorOf[tokenId];
        if (currentWeekCursor == 0) {
            // Need to do the initial binary search
            nftEpoch = _findTimestampNftEpoch(tokenId, currentTime, maxNftEpoch);
        } else {
            nftEpoch = nftEpochOf[tokenId];
        }

        if (nftEpoch == 0) nftEpoch = 1;

        IVotingEscrow.Point memory nftPoint = IVotingEscrow.Point(0, 0, 0, 0);
        (nftPoint.bias, nftPoint.slope, nftPoint.ts, nftPoint.blk) = votingEscrow.nftPointHistory(tokenId, nftEpoch);

        if (currentWeekCursor == 0) currentWeekCursor = (nftPoint.ts + WEEK - 1) / WEEK * WEEK;
        if (currentWeekCursor > time) return 0;
        if (currentWeekCursor < currentTime) currentWeekCursor = currentTime;

        IVotingEscrow.Point memory oldNftPoint = IVotingEscrow.Point(0, 0, 0, 0);

        for (uint i = 0; i < 50; i++) {
            if (currentWeekCursor >= lastTokenTime) break;

            if (currentWeekCursor >= nftPoint.ts && nftEpoch <= maxNftEpoch) {
                nftEpoch += 1;
                oldNftPoint.bias = nftPoint.bias;
                oldNftPoint.slope = nftPoint.slope;
                oldNftPoint.ts = nftPoint.ts;
                oldNftPoint.blk = nftPoint.blk;

                if (nftEpoch > maxNftEpoch) {
                    nftPoint = IVotingEscrow.Point(0, 0, 0, 0);
                } else {
                    (nftPoint.bias, nftPoint.slope, nftPoint.ts, nftPoint.blk) = votingEscrow.nftPointHistory(tokenId, nftEpoch);
                }
            } else {
                int128 dt = int128(int256(currentWeekCursor - oldNftPoint.ts));
                uint balanceOf = uint256(SignedMath.max(int256(oldNftPoint.bias - dt * oldNftPoint.slope), 0));
                if (balanceOf == 0 && nftEpoch > maxNftEpoch) break;
                if (balanceOf > 0 && veSupply[currentWeekCursor] > 0) {
                    toDistribute += _claimUpdate(balanceOf, tokenId, currentWeekCursor);
                }
                currentWeekCursor += WEEK;
            }
        }

        nftEpoch = Math.min(maxNftEpoch, nftEpoch - 1);
        nftEpochOf[tokenId] = nftEpoch;
        timeCursorOf[tokenId] = Math.min(currentWeekCursor, time);

        emit Claimed(tokenId, toDistribute, nftEpoch, maxNftEpoch);

        return toDistribute;
    }

    function _claimUpdate(uint balanceOf, uint tokenId, uint currentWeekCursor) internal returns (uint) {
        uint reward = balanceOf * tokensPerWeek[currentWeekCursor] / veSupply[currentWeekCursor] - claimed[tokenId][currentWeekCursor];
        claimed[tokenId][currentWeekCursor] += reward;
        return reward;
    }

    function _claimable(uint tokenId, uint currentWeek) internal view returns (uint) {
        uint toDistribute = 0;

        uint maxNftEpoch = votingEscrow.nftPointEpoch(tokenId);
        if (maxNftEpoch == 0) return 0;

        uint currentWeekCursor = timeCursorOf[tokenId];
        uint currentTime = startTime;
        uint nftEpoch = 0;
        if (currentWeekCursor == 0) {
            nftEpoch = _findTimestampNftEpoch(tokenId, currentTime, maxNftEpoch);
        } else {
            nftEpoch = nftEpochOf[tokenId];
        }
        if (nftEpoch == 0) nftEpoch = 1;
        IVotingEscrow.Point memory nftPoint = IVotingEscrow.Point(0, 0, 0, 0);
        (nftPoint.bias, nftPoint.slope, nftPoint.ts, nftPoint.blk) = votingEscrow.nftPointHistory(tokenId, nftEpoch);
        if (currentWeekCursor == 0) currentWeekCursor = (nftPoint.ts + WEEK - 1) / WEEK * WEEK;
        if (currentWeekCursor > currentWeek) return 0;
        if (currentWeekCursor < currentTime) currentWeekCursor = currentTime;

        IVotingEscrow.Point memory oldNftPoint = IVotingEscrow.Point(0, 0, 0, 0);
        for (uint i = 0; i < 255; i++) {
            if (currentWeekCursor >= lastTokenTime) break;
            if (currentWeekCursor >= nftPoint.ts && nftEpoch <= maxNftEpoch) {
                nftEpoch += 1;
                oldNftPoint.bias = nftPoint.bias;
                oldNftPoint.slope = nftPoint.slope;
                oldNftPoint.ts = nftPoint.ts;
                oldNftPoint.blk = nftPoint.blk;

                if (nftEpoch > maxNftEpoch) {
                    nftPoint = IVotingEscrow.Point(0, 0, 0, 0);
                } else {
                    (nftPoint.bias, nftPoint.slope, nftPoint.ts, nftPoint.blk) = votingEscrow.nftPointHistory(tokenId, nftEpoch);
                }
            } else {
                int128 dt = int128(int256(currentWeekCursor - oldNftPoint.ts));
                uint balanceOf = uint256(SignedMath.max(int256(oldNftPoint.bias - dt * oldNftPoint.slope), 0));
                if (balanceOf == 0 && nftEpoch > maxNftEpoch) break;
                if (balanceOf > 0 && veSupply[currentWeekCursor] > 0) {
                    toDistribute += balanceOf * tokensPerWeek[currentWeekCursor] / veSupply[currentWeekCursor] - claimed[tokenId][currentWeekCursor];
                }
                currentWeekCursor += WEEK;
            }
        }

        return toDistribute;
    }

    function _totalSupplyCheckpoint() internal {
        uint t = timeCursor;
        uint currentWeek = block.timestamp / WEEK * WEEK;
        votingEscrow.checkpoint();

        for (uint i = 0; i < 20; i++) {
            if (t >= currentWeek) {
                break;
            } else {
                uint epoch = _findTimestampEpoch(t);
                IVotingEscrow.Point memory pt = IVotingEscrow.Point(0, 0, 0, 0);
                (pt.bias, pt.slope, pt.ts, pt.blk) = votingEscrow.pointHistory(epoch);
                int128 dt = 0;
                if (t > pt.ts) {
                    dt = int128(int256(t - pt.ts));
                }
                veSupply[t] = uint(SignedMath.max(int256(pt.bias - pt.slope * dt), 0));
            }
            t += WEEK;
        }
        timeCursor = t;
    }

    function _tokenCheckpoint() internal {
        uint tokenBalance = lockToken.balanceOf(address(this));
        uint toDistribute = tokenBalance - tokenLastBalance;
        tokenLastBalance = tokenBalance;
        lastTokenTime = block.timestamp;
        uint currentWeek = lastTokenTime / WEEK * WEEK;
        tokensPerWeek[currentWeek] += toDistribute;
        tokensTotalWeek[currentWeek] = votingEscrow.totalLocked();

        emit CheckpointToken(block.timestamp, toDistribute);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
