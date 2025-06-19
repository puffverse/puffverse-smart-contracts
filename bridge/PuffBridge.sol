// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./lib/TransferHelper.sol";
import "./interfaces/IBurnMint.sol";

contract PuffBridge is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------- 1. Constants Definition -------------*/

    /*------------- 2. Storage -------------*/
    mapping(address => bool) public isOperator;

    // Bridge To Request
    address public tokenToBridge;
    bool public isLockMode;
    uint128 public bridgeFee; // RON fee Amount on Ronin or BNB fee Amount on BSC
    uint64 public latestSrcNonce;
    uint24 public srcChainId;
    uint24 public destChainId;
    mapping(uint64 => BridgeRequest) public requestMap; // srcNonce => BridgeRequest info

    // Bridge Receive
    uint8 public validatorThreshold; // validator voting threshold
    EnumerableSet.AddressSet private validators;
    mapping(uint64 => BridgeReceive) public receiveMap; // srcNonce of src chain => BridgeReceive info
    mapping(bytes32 => Approval) public approvals; // receiveHash => voting records
    mapping(address => uint64) public lastApproveSrcNonce; // validator => last srcNonce of approval

    /*------------- 3. Struct / Event -------------*/
    struct BridgeRequest {
        address sender;
        address receiver;
        uint128 amount;
        uint64 blockNumber;
        bytes extraData;
    }

    struct BridgeReceive {
        address receiver;
        uint128 amount;
        uint64 srcNonce;
        uint24 srcChainId;
        uint24 destChainId;
        bytes extraData;
    }

    // Store validator voting information
    struct Approval {
        mapping(address => bool) approvers; // whether validator has voted
        uint8 approvalCount; // current vote count
        uint64 srcNonce; // corresponding source chain nonce
        bool executed;
    }

    // Event definitions
    event BridgeRequestCreated(
        uint64 indexed srcNonce,
        address indexed sender,
        address indexed receiver,
        uint128 amount,
        uint64 blockNumber,
        uint24 srcChainId,
        uint24 destChainId,
        bool isLockMode,
        bytes extraData
    );

    event BridgeReceiveApproved(bytes32 indexed receiveHash, address indexed validator, uint64 srcNonce, uint8 currentApprovals, uint8 threshold);

    event BridgeReceiveExecuted(bytes32 indexed receiveHash, uint64 indexed srcNonce, address indexed receiver, uint128 amount);

    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event ValidatorThresholdChanged(uint8 oldThreshold, uint8 newThreshold);
    event BridgeFeeChanged(uint128 oldFee, uint128 newFee);
    event FeeWithdrawnToValidator(address indexed validator, uint256 amount);
    event OperatorSet(address indexed operator, bool isOperator);
    event ContractPaused(address indexed pauser);
    event ContractUnpaused(address indexed unpauser);

    /*------------- 4. Modifiers -------------*/
    modifier onlyOperator() {
        require(isOperator[msg.sender], "onlyOp");
        _;
    }

    modifier onlyValidator() {
        require(validators.contains(msg.sender), "!validator");
        _;
    }

    modifier onlyOperatorOrValidator() {
        require(isOperator[msg.sender] || validators.contains(msg.sender), "onlyOperatorOrValidator");
        _;
    }

    /*------------- 5.1 init -------------*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    // In the production environment, _owner is the multi-signature contract of the foundation
    function initialize(
        address _owner,
        address _tokenToBridge,
        uint128 _bridgeFee,
        uint64 _initFromNonce,
        uint24 _srcChainId,
        uint24 _destChainId,
        bool _isLockMode,
        address[] memory _validators,
        uint8 _validatorThreshold
    ) public initializer {
        __Ownable_init(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();

        require(_owner != address(0), "!owner");
        require(_tokenToBridge != address(0), "!token");
        require(_srcChainId != _destChainId, "same chain");
        require(_validators.length > 0, "!validators");
        require(_validatorThreshold > 0, "!threshold");
        require(_validatorThreshold <= _validators.length, "threshold > validators");

        tokenToBridge = _tokenToBridge;
        bridgeFee = _bridgeFee;
        latestSrcNonce = _initFromNonce;
        srcChainId = _srcChainId;
        destChainId = _destChainId;
        isLockMode = _isLockMode;

        // Add initial validators
        for (uint256 i = 0; i < _validators.length; i++) {
            require(_validators[i] != address(0), "!validator");
            require(validators.add(_validators[i]), "duplicate validator");
        }

        // Default value settings
        validatorThreshold = _validatorThreshold; // Set validator threshold
    }

    /*------------- 5.2 onlyOwner -------------*/
    function setOperator(address _operator, bool _isOperator) external onlyOwner {
        isOperator[_operator] = _isOperator;
        emit OperatorSet(_operator, _isOperator);
    }

    /// @notice Only owner can resume contract operation
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /**
     * @notice Add validator
     * @param _validator validator address
     */
    function addValidator(address _validator) external onlyOwner {
        require(_validator != address(0), "!validator");
        require(validators.add(_validator), "already exists");
        emit ValidatorAdded(_validator);
    }

    /**
     * @notice Remove validator
     * @param _validator validator address
     */
    function removeValidator(address _validator) external onlyOwner {
        require(validators.remove(_validator), "not exists");
        emit ValidatorRemoved(_validator);
    }

    /**
     * @notice Set validator voting threshold
     * @param _threshold new threshold
     */
    function setValidatorThreshold(uint8 _threshold) external onlyOwner {
        require(_threshold > 0, "!threshold");
        require(_threshold <= validators.length(), "threshold > validators");
        uint8 oldThreshold = validatorThreshold;
        validatorThreshold = _threshold;
        emit ValidatorThresholdChanged(oldThreshold, _threshold);
    }

    /**
     * @notice Set bridge fee
     * @param _bridgeFee new bridge fee
     */
    function setBridgeFee(uint128 _bridgeFee) external onlyOwner {
        uint128 feeLimit;
        if (block.chainid == 56) {
            feeLimit = 0.1 ether;
        } else {
            feeLimit = 100 ether;
        }
        require(_bridgeFee <= feeLimit, "fee exceeds limit");
        
        uint128 oldFee = bridgeFee;
        bridgeFee = _bridgeFee;
        emit BridgeFeeChanged(oldFee, _bridgeFee);
    }

    /*------------- 5.3 onlyOperator -------------*/
    /// @notice Both operator and validators can pause the contract
    function pause() external onlyOperatorOrValidator {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @notice Extract contract fees to validators
     */
    function withdrawFeeToValidators(address[] memory _validators, uint256[] memory amounts) external onlyOperator whenNotPaused nonReentrant {
        require(_validators.length > 0, "empty validators");
        require(_validators.length == amounts.length, "array length mismatch");

        uint256 totalAmount = 0;

        // Validate parameters and calculate total amount
        for (uint256 i = 0; i < _validators.length; i++) {
            require(_validators[i] != address(0), "!validator address");
            require(amounts[i] > 0, "!amount");
            require(validators.contains(_validators[i]), "not validator");

            // 🔒 Simplified duplicate check (limiting array size controls gas cost)
            for (uint256 j = 0; j < i; j++) {
                require(_validators[i] != _validators[j], "duplicate validator");
            }

            totalAmount += amounts[i];
        }

        // Check if contract balance is sufficient
        require(address(this).balance >= totalAmount, "insufficient balance");

        // Execute transfer to each validator
        for (uint256 i = 0; i < _validators.length; i++) {
            TransferHelper.safeTransferETH(_validators[i], amounts[i]);
            emit FeeWithdrawnToValidator(_validators[i], amounts[i]);
        }
    }

    /*------------- 5.4 function - onlyValidator -------------*/
    function approveBridgeTxHash(bytes32 receiveHash) external onlyValidator whenNotPaused {
        // Confirm receiveHash already exists in approvals
        Approval storage approval = approvals[receiveHash];
        require(approval.approvalCount > 0, "approval not exists");

        // Get corresponding BridgeReceive from receiveMap
        BridgeReceive memory bridgeReceive = receiveMap[approval.srcNonce];

        // Call internal function to handle voting
        _approveBridgeTx(receiveHash, bridgeReceive);
    }

    /**
     * @notice Validator votes to confirm cross-chain transactions
     * @param bridgeReceive cross-chain receive information
     */
    function approveBridgeTx(BridgeReceive memory bridgeReceive) public onlyValidator whenNotPaused {
        // Validate parameters
        require(bridgeReceive.receiver != address(0), "!receiver");
        require(bridgeReceive.amount > 0, "!amount");
        require(bridgeReceive.destChainId == srcChainId, "wrong chain");

        // Calculate hash of receive information
        bytes32 receiveHash = getBridgeReceiveHash(bridgeReceive);
        Approval storage approval = approvals[receiveHash];

        // If it's the first vote, store information
        if (approval.approvalCount == 0) {
            // 🔒 Security check: prevent srcNonce reuse
            require(receiveMap[bridgeReceive.srcNonce].receiver == address(0), "srcNonce already used");

            approval.srcNonce = bridgeReceive.srcNonce;
            // Store receive information
            receiveMap[bridgeReceive.srcNonce] = bridgeReceive;
        } else {
            // 🔒 Security check: ensure subsequent voting data is consistent with first vote
            BridgeReceive memory storedReceive = receiveMap[approval.srcNonce];
            require(
                storedReceive.receiver == bridgeReceive.receiver && storedReceive.amount == bridgeReceive.amount
                    && storedReceive.srcNonce == bridgeReceive.srcNonce && storedReceive.srcChainId == bridgeReceive.srcChainId
                    && storedReceive.destChainId == bridgeReceive.destChainId && keccak256(storedReceive.extraData) == keccak256(bridgeReceive.extraData),
                "bridgeReceive data mismatch"
            );
        }

        // Call internal function to handle voting
        _approveBridgeTx(receiveHash, bridgeReceive);
    }

    /*------------- 5.5 public -------------*/
    /**
     * @notice Lock or burn tokens to initiate cross-chain
     * @param amount cross-chain amount
     * @param receiver target chain receiving address
     */
    function lockOrBurn(uint256 amount, address receiver) external payable whenNotPaused {
        require(amount > 0, "!amount");
        require(receiver != address(0), "!receiver");
        require(msg.value == bridgeFee, "invalid bridge fee");
        // 🔒 Prevent overflow
        require(amount <= type(uint128).max, "amount too large");

        // Update nonce
        latestSrcNonce++;
        uint64 currentNonce = latestSrcNonce;

        // Record cross-chain request
        requestMap[currentNonce] = BridgeRequest({ sender: msg.sender, receiver: receiver, amount: uint128(amount), blockNumber: uint64(block.number), extraData: "" });

        // Lock or burn token
        if (isLockMode) {
            // Lock mode: transfer token to contract
            TransferHelper.safeTransferFrom(tokenToBridge, msg.sender, address(this), amount);
        } else {
            // Burn mode: burn token
            IBurnMint(tokenToBridge).burnFrom(msg.sender, amount);
        }

        emit BridgeRequestCreated(currentNonce, msg.sender, receiver, uint128(amount), uint64(block.number), srcChainId, destChainId, isLockMode, "");
    }

    /**
     * @notice Manually execute approved cross-chain receive (for handling automatic execution failures)
     * @param bridgeReceive cross-chain receive information
     */
    function releaseOrMint(BridgeReceive memory bridgeReceive) external whenNotPaused {
        bytes32 receiveHash = getBridgeReceiveHash(bridgeReceive);
        Approval storage approval = approvals[receiveHash];

        require(approval.approvalCount >= validatorThreshold, "insufficient approvals");
        require(!approval.executed, "already executed");

        approval.executed = true;
        _executeBridgeReceive(bridgeReceive, receiveHash);
    }

    /*------------- 5.6 view -------------*/
    // For upgrade version verification
    function versionInfo() external pure returns (uint256 version, string memory desc) {
        return (1, "init");
    }

    function getValidatorInfo() external view returns (address[] memory, uint8 _validatorThreshold) {
        return (validators.values(), validatorThreshold);
    }

    /**
     * @notice Get validator count
     */
    function getValidatorCount() external view returns (uint256) {
        return validators.length();
    }

    /**
     * @notice Check if address is validator
     */
    function isValidator(address account) external view returns (bool) {
        return validators.contains(account);
    }

    /**
     * @notice Get voting status of cross-chain receive information
     */
    function getApprovalInfo(BridgeReceive memory bridgeReceive) external view returns (uint8 approvalCount, bool executed) {
        bytes32 receiveHash = getBridgeReceiveHash(bridgeReceive);
        Approval storage approval = approvals[receiveHash];
        return (approval.approvalCount, approval.executed);
    }

    function getBridgeReceiveInfo(uint64 srcNonce, address validator)
        external
        view
        returns (BridgeReceive memory, uint8 approvalCount, bool executed, bool validatorApproved)
    {
        BridgeReceive memory bridgeReceive = receiveMap[srcNonce];

        // If no corresponding receive information is found, return empty information
        if (bridgeReceive.receiver == address(0)) {
            return (bridgeReceive, 0, false, false);
        }

        // Calculate hash of receive information and get voting status
        bytes32 receiveHash = getBridgeReceiveHash(bridgeReceive);
        Approval storage approval = approvals[receiveHash];

        return (bridgeReceive, approval.approvalCount, approval.executed, approval.approvers[validator]);
    }

    function getTargetBridgeReceiveFromRequest(uint64 srcNonce) external view returns (BridgeRequest memory, BridgeReceive memory) {
        // Get corresponding cross-chain request information
        BridgeRequest memory srcRequest = requestMap[srcNonce];

        // Check if request exists
        require(srcRequest.receiver != address(0), "request not found");

        BridgeReceive memory receiveForDestChain = BridgeReceive({
            receiver: srcRequest.receiver,
            amount: srcRequest.amount,
            srcNonce: srcNonce,
            srcChainId: srcChainId, // Current chain as source chain
            destChainId: destChainId, // Target chain ID
            extraData: srcRequest.extraData
        });

        // Assemble BridgeReceive struct
        return (srcRequest, receiveForDestChain);
    }

    /**
     * @notice Check if validator has voted for specific cross-chain transaction
     */
    function hasValidatorApproved(BridgeReceive memory bridgeReceive, address validator) external view returns (bool) {
        bytes32 receiveHash = getBridgeReceiveHash(bridgeReceive);
        return approvals[receiveHash].approvers[validator];
    }

    /**
     * @notice Calculate hash value of BridgeReceive
     */
    function getBridgeReceiveHash(BridgeReceive memory bridgeReceive) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                bridgeReceive.receiver,
                bridgeReceive.amount,
                bridgeReceive.srcNonce,
                bridgeReceive.srcChainId,
                bridgeReceive.destChainId,
                bridgeReceive.extraData
            )
        );
    }
    /*------------- 5.7 internal -------------*/
    /**
     * @notice Execute cross-chain receive: release or mint token
     */

    function _executeBridgeReceive(BridgeReceive memory bridgeReceive, bytes32 receiveHash) internal {
        if (isLockMode) {
            // Release mode: release token from contract
            TransferHelper.safeTransfer(tokenToBridge, bridgeReceive.receiver, bridgeReceive.amount);
        } else {
            // Mint mode: mint new token
            IBurnMint(tokenToBridge).mint(bridgeReceive.receiver, bridgeReceive.amount);
        }

        emit BridgeReceiveExecuted(receiveHash, bridgeReceive.srcNonce, bridgeReceive.receiver, bridgeReceive.amount);
    }

    /**
     * @notice Internal function to handle voting logic
     */
    function _approveBridgeTx(bytes32 receiveHash, BridgeReceive memory bridgeReceive) internal {
        Approval storage approval = approvals[receiveHash];

        // Check if already executed
        require(!approval.executed, "already executed");

        // Check if already voted
        require(!approval.approvers[msg.sender], "already approved");

        // Record vote
        approval.approvers[msg.sender] = true;
        approval.approvalCount++;
        lastApproveSrcNonce[msg.sender] = bridgeReceive.srcNonce;

        emit BridgeReceiveApproved(receiveHash, msg.sender, bridgeReceive.srcNonce, approval.approvalCount, validatorThreshold);

        // If threshold is reached, execute cross-chain transfer
        if (approval.approvalCount >= validatorThreshold) {
            approval.executed = true;
            _executeBridgeReceive(bridgeReceive, receiveHash);
        }
    }
}
