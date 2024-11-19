// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import '@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/Base64.sol';

import '../interfaces/IVotingEscrow.sol';
import '../interfaces/IFeeDistributor.sol';
import '../interfaces/ISvgBuilderClient.sol';

/**
# Voting escrow to have time-weighted votes
# Votes have a weight depending on time, so that users are committed
# to the future of (whatever they are voting for).
# The weight in this implementation is linear, and lock cannot be more than maxtime:
# w ^
# 1 +        /
#   |      /
#   |    /
#   |  /
#   |/
# 0 +--------+------> time
#       maxtime (4 years)
*/
contract VotingEscrow is
IVotingEscrow,
ERC721EnumerableUpgradeable,
UUPSUpgradeable,
AccessControlEnumerableUpgradeable,
ReentrancyGuardUpgradeable,
PausableUpgradeable,
ERC721HolderUpgradeable
{
    using Strings for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 internal constant WEEK = 1 weeks;
    uint public constant MAX_TIME = 4 * 365 * 86400;
    uint internal constant MULTIPLIER = 1 ether; //1e18
    uint256 public constant MIN_LOCK_AMOUNT = 1e17;
    IERC20 public immutable LOCK_TOKEN;
    IERC721 public immutable BOOST_NFT;
    IERC721 public immutable SPEED_NFT;
    ISvgBuilderClient private immutable SVG_BUILDER_CLIENT;

    event Deposit(
        address indexed provider,
        uint tokenId,
        uint value,
        uint point,
        uint indexed locktime,
        uint timestamp
    );

    event Withdraw(address indexed provider, uint tokenId, uint value, uint ts);
    event ForceWithdraw(address indexed provider, uint tokenId, uint withdrawAmount, uint penalty, uint ts);
    event Supply(uint prevSupply, uint supply);
    event CanTransfer(bool prevStat, bool afterStat);
    event CanForceWithdraw(bool prevStat, bool afterStat);

    uint public totalLocked;
    mapping(uint => LockedBalance) public lockedBalances;
    //epoch of global
    uint public epoch;
    mapping(uint => Point) public override pointHistory; // epoch -> unsigned point
    mapping(uint => int128) public slopeChanges; // time -> signed slope change

    //epoch of NFT
    mapping(uint => uint) public nftPointEpoch;
    mapping(uint => Point[1000000000]) public nftPointHistory; // user -> Point[user_epoch]
    mapping(uint => uint) public boostNFT;
    mapping(uint => uint) public speedNFT;

    /// @dev Current count of token
    uint256 public maxTokenId;
    uint256 public sumLockedTime;

    mapping(address => uint256) private lastBlockNumberCalled;
    // the final owner (for burnt NFT)
    mapping(uint256 => address) public latestOwner;

    // forced withdraw config
    uint256 public minRatio;
    uint256 public maxRatio;
    IFeeDistributor public feeDistributor;
    mapping(uint => uint) public override forcePenaltyAmount;
    address public forcePenaltyReciever;

    constructor(IERC20 _lockToken, IERC721 _boostNFT, IERC721 _speedNFT, ISvgBuilderClient _svgBuilderClient) {
        require(address(_lockToken) != address(0), "invalid token");
        LOCK_TOKEN = _lockToken;
        require(address(_boostNFT) != address(0), "invalid boost nft");
        BOOST_NFT = _boostNFT;
        SPEED_NFT = _speedNFT;
        SVG_BUILDER_CLIENT = _svgBuilderClient;
        _disableInitializers();
    }


    function initialize(address _admin, address _forcePenaltyReciever, uint _minRatio, uint _maxRatio) public initializer {
        __ERC721_init("vePuff", "vePuff");
        __AccessControl_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init();


        require(_minRatio <= _maxRatio, "Invalid: minRatio must be <= maxRatio");
        require(_maxRatio < MULTIPLIER, "Invalid: maxRatio must be < MULTIPLIER");
        minRatio = _minRatio;
        maxRatio = _maxRatio;
        forcePenaltyReciever = _forcePenaltyReciever;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);

        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;
    }

    modifier oncePerBlock(address user) {
        require(lastBlockNumberCalled[user] < block.number, "once per block");
        lastBlockNumberCalled[user] = block.number;
        _;
    }

    function calculatePoint(uint _lockAmount, uint _duration, uint _boostTokenId, uint _speedTokenId) internal pure returns (uint) {
        uint point = _lockAmount;
        if (_duration <= 4 * WEEK) {
            point *= 100;
        } else if (_duration <= 12 * WEEK) {
            point = point * 120;
        } else if (_duration <= 24 * WEEK) {
            point = point * 130;
        } else if (_duration <= 48 * WEEK) {
            point = point * 150;
        } else if (_duration <= 96 * WEEK) {
            point = point * 180;
        } else {
            point = point * 200;
        }
        if (_boostTokenId > 0) {
            point = point * 130 / 100;
        }else if (_speedTokenId > 0) {
            point = point * 110 / 100;
        }
        return point / 100;
    }

    function createLock(
        uint _lockAmount,
        uint _lockDuration,
        address _for,
        uint _boostTokenId,
        uint _speedTokenId
    ) external whenNotPaused nonReentrant oncePerBlock(_for) returns (uint) {
        require(_lockDuration > 0 && _lockDuration <= MAX_TIME, 'Invalid duration');
        uint unlockTime = (block.timestamp + _lockDuration) / WEEK * WEEK;
        // LockTime is Can only increase lock duration rounded down to weeks
        require(_lockAmount >= MIN_LOCK_AMOUNT, 'Invalid amount');
        //need more than 0.1
        require(unlockTime > block.timestamp, 'Can only lock until time in the future');
        _lockDuration = unlockTime - block.timestamp;
        uint lockPoint = calculatePoint(_lockAmount, _lockDuration, _boostTokenId, _speedTokenId);

        ++maxTokenId;
        uint tokenId = maxTokenId;
        _safeMint(_for, tokenId);
        if (_boostTokenId > 0) {
            BOOST_NFT.safeTransferFrom(msg.sender, address(this), _boostTokenId);
        }else if (_speedTokenId > 0) {
            SPEED_NFT.safeTransferFrom(msg.sender, address(this), _speedTokenId);
        }
        boostNFT[tokenId] = _boostTokenId;
        speedNFT[tokenId] = _speedTokenId;

        sumLockedTime = sumLockedTime + _lockDuration;
        // add locked time
        _depositFor(tokenId, _lockAmount, lockPoint, unlockTime, lockedBalances[tokenId]);
        return tokenId;
    }

    function _depositFor(
        uint tokenId,
        uint lockAmount,
        uint lockPoint,
        uint unlockTime,
        LockedBalance memory lockedBalance
    ) internal {
        uint totalLockedBefore = totalLocked;
        totalLocked = totalLockedBefore + lockAmount;

        LockedBalance memory oldLockedBalance;

        (oldLockedBalance.amount, oldLockedBalance.point, oldLockedBalance.end) = (lockedBalance.amount, lockedBalance.point, lockedBalance.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        if (lockAmount != 0 && unlockTime != 0) {
            lockedBalance.begin = block.timestamp;
        }

        uint256 int128Max = 2 ** 127 - 1;
        require(lockAmount <= int128Max, "Overflow 1: lockAmount exceeds int128 max");
        require(lockPoint <= int128Max, "Overflow 2: lockPoint exceeds int128 max");

        lockedBalance.amount += int128(int256(lockAmount));
        lockedBalance.point += int128(int256(lockPoint));
        if (unlockTime != 0) {
            lockedBalance.end = unlockTime;
        }
        lockedBalances[tokenId] = lockedBalance;

        // Possibilities:
        // Both oldLockedBalance.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(tokenId, oldLockedBalance, lockedBalance);

        if (lockAmount > 0) {
            LOCK_TOKEN.safeTransferFrom(msg.sender, address(this), lockAmount);
        }

        emit Deposit(msg.sender, tokenId, lockAmount, lockPoint, lockedBalance.end, block.timestamp);
        emit Supply(totalLockedBefore, totalLocked);
    }

    function withdraw(uint tokenId) external whenNotPaused nonReentrant oncePerBlock(msg.sender) {
        require(_ownerOf(tokenId) == msg.sender, "ERC721: transfer caller is not owner");

        LockedBalance memory locked = lockedBalances[tokenId];
        require(block.timestamp >= locked.end, "Lock not expired");

        feeDistributor.claimVE(tokenId);

        uint value = uint(int256(locked.amount));

        lockedBalances[tokenId] = LockedBalance(0, 0, 0, 0);
        uint supplyBefore = totalLocked;
        totalLocked = supplyBefore - value;

        // old_locked can have either expired <= timestamp or zero end
        // locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(tokenId, locked, LockedBalance(0, 0, 0, 0));

        LOCK_TOKEN.safeTransfer(msg.sender, value);
        uint boostNftId = boostNFT[tokenId];
        if (boostNftId > 0) {
            BOOST_NFT.safeTransferFrom(address(this), msg.sender, boostNftId);
            delete boostNFT[tokenId];
        }
        uint speedNftId = speedNFT[tokenId];
        if (speedNftId > 0) {
            SPEED_NFT.safeTransferFrom(address(this), msg.sender, speedNftId);
            delete speedNFT[tokenId];
        }
        _burn(tokenId);
        // save latest owner
        latestOwner[tokenId] = msg.sender;
        emit Withdraw(msg.sender, tokenId, value, block.timestamp);
        emit Supply(supplyBefore, totalLocked);
    }

    function forceWithdraw(uint tokenId) external whenNotPaused nonReentrant oncePerBlock(msg.sender) {
        require(_ownerOf(tokenId) == msg.sender, "Not owner");

        LockedBalance memory locked = lockedBalances[tokenId];
        require(locked.amount > 0, "Not exist");
        require(locked.end > block.timestamp, "Pls use withdraw");

        feeDistributor.claimVE(tokenId);

        uint256 unlockAmount = uint256(uint128(locked.amount));

        uint256 timeLeft = locked.end - block.timestamp;
        uint256 penalty = unlockAmount * (maxRatio - (block.timestamp - locked.begin) * minRatio / (locked.end - locked.begin)) / MULTIPLIER;
        require(penalty < unlockAmount, "Invalid penalty");

        _checkpoint(tokenId, locked, LockedBalance(0, 0, 0, 0));
        _burn(tokenId);
        latestOwner[tokenId] = msg.sender;
        lockedBalances[tokenId] = LockedBalance(0, 0, 0, 0);
        sumLockedTime = sumLockedTime - timeLeft;

        uint supplyBefore = totalLocked;
        totalLocked = supplyBefore - unlockAmount;
        //transfer
        LOCK_TOKEN.safeTransfer(msg.sender, unlockAmount - penalty);
        uint boostNftId = boostNFT[tokenId];
        if (boostNftId > 0) {
            BOOST_NFT.safeTransferFrom(address(this), msg.sender, boostNftId);
            delete boostNFT[tokenId];
        }
        uint speedNftId = speedNFT[tokenId];
        if (speedNftId > 0) {
            SPEED_NFT.safeTransferFrom(address(this), msg.sender, speedNftId);
            delete speedNFT[tokenId];
        }

        if (penalty > 0) {
            if (forcePenaltyReciever != address(0)) {
                LOCK_TOKEN.safeTransfer(forcePenaltyReciever, penalty * 20 / 100);
                penalty -= (penalty * 20 / 100);
            }
            require(address(feeDistributor) != address(0), "FeeDistributor not set");
            LOCK_TOKEN.safeTransfer(address(feeDistributor), penalty);
            // to penalty account
            feeDistributor.checkpoint();
            forcePenaltyAmount[block.timestamp / WEEK * WEEK] += penalty;
        }
        //emit Event
        emit ForceWithdraw(msg.sender, tokenId, unlockAmount, penalty, block.timestamp);
        emit Supply(supplyBefore, totalLocked);
    }

    function _checkpoint(
        uint tokenId,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        Point memory userOldPoint;
        Point memory userNewPoint;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint currentEpoch = epoch;

        if (tokenId != 0) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                userOldPoint.slope = oldLocked.point / int128(int256(MAX_TIME));
                userOldPoint.bias = userOldPoint.slope * int128(int256(oldLocked.end - block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                userNewPoint.slope = newLocked.point / int128(int256(MAX_TIME));
                userNewPoint.bias = userNewPoint.slope * int128(int256(newLocked.end - block.timestamp));
            }

            // Read values of scheduled changes in the slope
            // oldLocked.end can be in the past and in the future
            // newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[newLocked.end];
                }
            }
        }

        Point memory last_point = Point({bias : 0, slope : 0, ts : block.timestamp, blk : block.number});
        if (currentEpoch > 0) {
            last_point = pointHistory[currentEpoch];
        }
        uint last_checkpoint = last_point.ts;
        // initial_last_point is used for extrapolation to calculate block number(approximately, for *At methods) and save them
        // Deep copy (share same reference with last_point will cause dirty memory)
        Point memory initial_last_point = Point({bias : last_point.bias, slope : last_point.slope, ts : last_point.ts, blk : last_point.blk});

        uint block_slope = 0;
        // dblock/dt
        if (block.timestamp > last_point.ts) {
            block_slope = (MULTIPLIER * (block.number - last_point.blk)) / (block.timestamp - last_point.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint t_i = (last_checkpoint / WEEK) * WEEK;
            for (uint i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK;
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slopeChanges[t_i];
                }
                last_point.bias -= last_point.slope * int128(int256(t_i - last_checkpoint));
                last_point.slope += d_slope;
                if (last_point.bias < 0) {
                    // This can happen
                    last_point.bias = 0;
                }
                if (last_point.slope < 0) {
                    // This cannot happen - just in case
                    last_point.slope = 0;
                }
                last_checkpoint = t_i;
                last_point.ts = t_i;
                last_point.blk = initial_last_point.blk + (block_slope * (t_i - initial_last_point.ts)) / MULTIPLIER;
                currentEpoch += 1;
                if (t_i == block.timestamp) {
                    last_point.blk = block.number;
                    break;
                } else {
                    pointHistory[currentEpoch] = last_point;
                }
            }
        }

        epoch = currentEpoch;
        // Now pointHistory is filled until t=now

        if (tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            last_point.slope += (userNewPoint.slope - userOldPoint.slope);
            last_point.bias += (userNewPoint.bias - userOldPoint.bias);
            if (last_point.slope < 0) {
                last_point.slope = 0;
            }
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
        }

        // Record the changed point into history
        pointHistory[currentEpoch] = last_point;

        if (tokenId != 0) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [newLocked.end]
            // and add old_user_slope to [oldLocked.end]
            if (oldLocked.end > block.timestamp) {
                // oldDslope was <something> - userOldPoint.slope, so we cancel that
                oldDslope += userOldPoint.slope;
                if (newLocked.end == oldLocked.end) {
                    oldDslope -= userNewPoint.slope;
                    // It was a new deposit, not extension
                }
                slopeChanges[oldLocked.end] = oldDslope;
            }

            if (newLocked.end > block.timestamp) {
                if (newLocked.end > oldLocked.end) {
                    newDslope -= userNewPoint.slope;
                    // old slope disappeared at this point
                    slopeChanges[newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }
            // Now handle user history
            uint nft_epoch = nftPointEpoch[tokenId] + 1;

            nftPointEpoch[tokenId] = nft_epoch;
            userNewPoint.ts = block.timestamp;
            userNewPoint.blk = block.number;
            nftPointHistory[tokenId][nft_epoch] = userNewPoint;
        }
    }

    function checkpoint() external whenNotPaused {
        _checkpoint(0, LockedBalance(0, 0, 0, 0), LockedBalance(0, 0, 0, 0));
    }


    function configMinRatio(uint256 _minRatio) external onlyRole(ADMIN_ROLE) {
        require(_minRatio <= maxRatio, "E1");
        minRatio = _minRatio;
    }

    function configForcePenaltyReciever(address newAddr) external onlyRole(ADMIN_ROLE) {
        forcePenaltyReciever = newAddr;
    }

    function configMaxRatio(uint256 _maxRatio) external onlyRole(ADMIN_ROLE) {
        require(_maxRatio < MULTIPLIER, "E1");
        require(_maxRatio >= minRatio, "E2");
        maxRatio = _maxRatio;
    }

    function configFeeDistributor(IFeeDistributor _feeDistributor) external onlyRole(ADMIN_ROLE) {
        if (address(feeDistributor) != address(0)) {
            require(hasRole(ADMIN_ROLE, msg.sender), "only admin");
        }
        feeDistributor = _feeDistributor;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function nftOwner(uint tokenId) external view returns (address) {
        address owner = latestOwner[tokenId];
        if (owner == address(0)) {
            owner = ownerOf(tokenId);
        }
        return owner;
    }

    function getLockedDetail(uint tokenId) external view returns (LockedBalance memory) {
        return lockedBalances[tokenId];
    }

    function getPenalty(uint tokenId) external view returns(uint256) {
        uint256 penalty = 0;
        LockedBalance memory locked = lockedBalances[tokenId];
        if (locked.amount > 0 && locked.end > block.timestamp) {
            uint256 unlockAmount = uint256(uint128(locked.amount));
            penalty = unlockAmount * (maxRatio - (block.timestamp - locked.begin) * minRatio / (locked.end - locked.begin)) / MULTIPLIER;
        }
        return penalty;
    }

    function userLocked(address account) external view returns (uint256 amount, uint256 point) {
        uint256[] memory tokenIds = tokensOfOwner(account);
        for (uint i = 0; i < tokenIds.length; i ++) {
            LockedBalance memory lockedBalance = lockedBalances[tokenIds[i]];
            amount += uint256(int256(lockedBalance.amount));
            point += uint256(int256(lockedBalance.point));
        }
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        LockedBalance memory lockedBalance = lockedBalances[tokenId];
        string memory output = SVG_BUILDER_CLIENT.buildSvg(tokenId, uint256(uint128(lockedBalance.amount)), lockedBalance.end);
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "#', tokenId.toString(), '", "description": "Apollox DAO VE", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));
        return output;
    }

    function powerOfNftAt(uint tokenId, uint timestamp) public view returns (uint){
        uint thisEpoch = nftPointEpoch[tokenId];
        if (thisEpoch == 0) {
            return 0;
        } else {
            Point memory lastPoint = nftPointHistory[tokenId][thisEpoch];
            require(timestamp >= lastPoint.ts, "Invalid timestamp");

            lastPoint.bias -= lastPoint.slope * int128(int256(timestamp) - int256(lastPoint.ts));
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return uint(int256(lastPoint.bias));
        }
    }

    function powerOfNft(uint tokenId) external view returns (uint){
        return powerOfNftAt(tokenId, block.timestamp);
    }

    function powerOfAccount(address account) external view returns (uint){
        uint256[] memory tokenIds = tokensOfOwner(account);
        uint power = 0;
        for (uint i = 0; i < tokenIds.length; i++) {
            power += powerOfNftAt(tokenIds[i], block.timestamp);
        }
        return power;
    }

    function powerOfAccountAt(address account, uint timestamp) external view returns (uint){
        uint256[] memory tokenIds = tokensOfOwner(account);
        uint power = 0;
        for (uint i = 0; i < tokenIds.length; i++) {
            power += powerOfNftAt(tokenIds[i], timestamp);
        }
        return power;
    }

    function findTimestampEpoch(uint timestamp, uint maxEpoch) internal view returns (uint) {
        uint min = 0;
        uint max = maxEpoch;

        for (uint i = 0; i < 128; i ++) {
            if (min >= max) {
                break;
            }
            uint mid = (min + max + 1) / 2;
            if (pointHistory[mid].ts <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    function supplyAt(Point memory lastPoint, uint timestamp) internal view returns (uint) {
        uint currentTime = lastPoint.ts / WEEK * WEEK;
        for (uint i = 0; i < 255; i ++) {
            currentTime += WEEK;
            int128 dSlope = 0;
            if (currentTime > timestamp) {
                currentTime = timestamp;
            } else {
                dSlope = slopeChanges[currentTime];
            }
            lastPoint.bias -= lastPoint.slope * int128(uint128(currentTime - lastPoint.ts));
            if (currentTime == timestamp) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.ts = currentTime;
        }
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint(uint128(lastPoint.bias));
    }

    function totalPowerAt(uint timestamp) public view returns (uint) {
        uint currentEpoch = epoch;
        if (timestamp != block.timestamp) {
            currentEpoch = findTimestampEpoch(timestamp, currentEpoch);
        }
        if (currentEpoch == 0) {
            return 0;
        }
        Point memory lastPoint = pointHistory[currentEpoch];
        return supplyAt(lastPoint, timestamp);
    }

    function totalPower() external view returns (uint) {
        return totalPowerAt(block.timestamp);
    }

    function tokensOfOwner(address owner) public view returns (uint256[] memory) {
        uint balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint i = 0; i < balance; i ++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721EnumerableUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        require(_ownerOf(tokenId) == address(0) || to == address(0));
        return super._update(to, tokenId, auth);
    }

}
