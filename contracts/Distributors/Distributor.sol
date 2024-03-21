//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/IERC20.sol";
import "../lib/Address.sol";
import "../lib/IUniswapV2Router02.sol";
import "../lib/ReentrancyGuard.sol";
import "../lib/TransferHelper.sol";
import "../interfaces/IImplementation.sol";
import "../lib/EnumerableSet.sol";

interface IToken {
    function owner() external view returns (address);
}

contract DistributorData {

    // Token Token Contract
    address public Token;

    // Reward Token Contract
    address public rewardToken;

    // Uniswap Router
    address public router;

    // User info
    struct UserInfo {
        uint256 balance;
        uint256 totalClaimed;
        uint256 totalExcluded;
        bool isRewardExempt;
    }
    
    // shareholder fields
    mapping ( address => UserInfo ) public userInfo;
    
    // shares math and fields
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public dividendsPerShare;
    uint256 internal constant PRECISION = 10 ** 18;
    
    // 0.01 minimum bnb distribution
    uint256 public minDistribution;

    // current index in shareholder array 
    uint256 public currentIndex;
    
    // number of iterations per transaction
    uint256 public iterations_per_transfer;

    // Auto distribute rewards or claim only
    bool public autoDistribute;

    // Path
    address[] public path;

    // List of all holders
    EnumerableSet.AddressSet internal holders;

    modifier onlyToken() {
        require(msg.sender == Token, 'Not Permitted'); 
        _;
    }
    
    modifier onlyTokenOwner() {
        require(msg.sender == IToken(Token).owner(), 'Not Permitted'); 
        _;
    }

}

/** Distributes Tokens To Token Holders */
contract Distributor is DistributorData, ReentrancyGuard, IImplementation {

    function __init__(bytes calldata payload) external {
        require(Token == address(0), 'Already Initialized');
        (
            Token,
            rewardToken,
            router,
            path,
            minDistribution,
            iterations_per_transfer,
            autoDistribute
        ) = abi.decode(payload, (address, address, address, address[], uint256, uint256, bool));
        require(Token != address(0), 'Invalid Token');

        // not entered
        _status = _NOT_ENTERED;
        
        // reward exempt
        userInfo[address(this)].isRewardExempt = true;
    }
    
    ///////////////////////////////////////////////
    //////////      Only Token Owner    ///////////
    ///////////////////////////////////////////////
    
    /** Withdraw Assets Mistakingly Sent To Distributor, And For Upgrading If Necessary */
    function withdraw(bool bnb, address _token, uint256 amount) external onlyTokenOwner {
        if (bnb) {
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            TransferHelper.safeTransfer(_token, msg.sender, amount);
        }
    }
    
    /** Sets Distibution Criteria */
    function setMinDistribution(uint256 _minDistribution) external onlyTokenOwner {
        minDistribution = _minDistribution;
    }

    function setRewardToken(address token) external onlyTokenOwner {
        rewardToken = token;
    }

    function setCurrentIndex(uint256 index) external onlyTokenOwner {
        currentIndex = index;
    }

    function setIterationsPerTransfer(uint256 iterations) external onlyTokenOwner {
        iterations_per_transfer = iterations;
    }

    function setAutoDistribute(bool auto_) external onlyTokenOwner {
        autoDistribute = auto_;
    }

    function setToken(address _Token) external onlyTokenOwner {
        Token = _Token;
    }

    function setRouter(address _router) external onlyTokenOwner {
        router = _router;
    }

    function setPath(address[] calldata _path) external onlyTokenOwner {
        path = _path;
    }
    
    ///////////////////////////////////////////////
    //////////    Only Token Contract   ///////////
    ///////////////////////////////////////////////

    function setRewardExempt(address wallet, bool rewardless) external onlyToken {
        userInfo[wallet].isRewardExempt = rewardless;
        if (userInfo[wallet].balance > 0 && rewardless) {
            totalShares = totalShares - userInfo[wallet].balance;
            delete userInfo[wallet].balance;
            delete userInfo[wallet].totalExcluded;
            if (EnumerableSet.contains(holders, wallet)) {
                EnumerableSet.remove(holders, wallet);
            }
        }
    }
    
    /** Sets Share For User */
    function setShare(address shareholder, uint256 amount) external onlyToken {

        if (userInfo[shareholder].isRewardExempt) {
            return;
        }

        if (userInfo[shareholder].balance == 0 && amount > 0) {
            EnumerableSet.add(holders, shareholder);
        } else if (userInfo[shareholder].balance > 0 && amount == 0) {
            if (EnumerableSet.contains(holders, shareholder)) {
                EnumerableSet.remove(holders, shareholder);
            }
        }

        if(userInfo[shareholder].balance > 0 && !Address.isContract(shareholder)){
            _claimRewards(shareholder);
        }

        totalShares = ( totalShares + amount ) - userInfo[shareholder].balance;
        userInfo[shareholder].balance = amount;
        userInfo[shareholder].totalExcluded = getCumulativeDividends(userInfo[shareholder].balance);
    }
    
    ///////////////////////////////////////////////
    //////////      Public Functions    ///////////
    ///////////////////////////////////////////////
    
    function batchClaim(address[] calldata shareholders) external {
        uint len = shareholders.length;
        for (uint i = 0; i < len;) {
            _claimRewards(shareholders[i]);
            unchecked { ++i; }
        }
    }

    function claimRewards() external {
        _claimRewards(msg.sender);
    }

    function process() external {
        if (autoDistribute) {
            _process(iterations_per_transfer);
        }
    }

    function processSetNumberOfIterations(uint256 iterations) external {
        _process(iterations);
    }

    function giveRewards(uint256 amount) external payable{
        require(totalShares > 0, "No Shares");

        uint256 rewards = 0;
        if (rewardToken == address(0)) {
            require(msg.value == amount, "Invalid Amount");
            rewards = msg.value;
        } else {
            require(msg.value == 0, "Invalid Value Sent");
            require(IERC20(rewardToken).balanceOf(msg.sender) >= amount, "Insufficient Balance");
            require(IERC20(rewardToken).allowance(msg.sender, address(this)) >= amount, "Insufficient Allowance");

            // transfer in tokens, noting the amount received to work with tax-on-transfer tokens
            uint256 balBefore = IERC20(rewardToken).balanceOf(address(this));
            TransferHelper.safeTransferFrom(rewardToken, msg.sender, address(this), amount);
            uint256 balAfter = IERC20(rewardToken).balanceOf(address(this));
            require(balAfter >= balBefore, "Transfer Failed");
            unchecked {
                rewards = balAfter - balBefore;
            }
        }
        unchecked {
            totalDividends += rewards;
            dividendsPerShare += ( rewards * PRECISION ) / totalShares;
        }
    }

    function giveBNBRewards() external payable {
        require(totalShares > 0, "No Shares");
        unchecked {
            totalDividends += msg.value;
            dividendsPerShare += ( msg.value * PRECISION ) / totalShares;
        }
    }

    function giveRewards() external payable {
        _onReceive();
    }

    receive() external payable {
        _onReceive();
    }


    ///////////////////////////////////////////////
    //////////    Internal Functions    ///////////
    ///////////////////////////////////////////////


    function _claimRewards(address shareholder) internal nonReentrant {
        if(userInfo[shareholder].balance == 0){ return; }
        
        uint256 pending = pendingRewards(shareholder);
        userInfo[shareholder].totalExcluded = getCumulativeDividends(userInfo[shareholder].balance);
        if (pending > 0) {
            if (rewardToken == address(0)) {
                (bool s,) = payable(shareholder).call{value: pending}("");
                if (s) {
                    unchecked {
                        userInfo[shareholder].totalClaimed += pending;
                    }
                }
            } else {
                TransferHelper.safeTransfer(rewardToken, shareholder, pending);
                unchecked {
                    userInfo[shareholder].totalClaimed += pending;
                }
            }
        }
    }

    function _process(uint256 iterations) internal {
        uint256 shareholderCount = EnumerableSet.length(holders);
        if(shareholderCount == 0) { return; }
        if (iterations > shareholderCount) {
            iterations = shareholderCount;
        }

        for (uint i = 0; i < iterations;) {

            // if index overflows, reset to 0
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }

            // fetch holder at current index
            address holder = EnumerableSet.at(holders, currentIndex);

            if (holder != address(0) && shouldDistribute(holder)) {
                _claimRewards(holder);
            }

            unchecked { ++i; ++currentIndex; }
        }
    }

    function _onReceive() internal {
        if (totalShares == 0) {
            return;
        }
        
        uint256 rewards = 0;
        if (rewardToken == address(0)) {
            rewards = msg.value;
        } else {
            // swap bnb for reward tokens
            uint256 balBefore = IERC20(rewardToken).balanceOf(address(this));
            IUniswapV2Router02(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(1, path, address(this), block.timestamp + 100);
            uint256 balAfter = IERC20(rewardToken).balanceOf(address(this));
            require(balAfter >= balBefore, "Swap Failed");
            unchecked {
                rewards = balAfter - balBefore;
            }
        }

        // add both bnb and tokens to rewards
        unchecked {
            totalDividends += rewards;
            dividendsPerShare += ( rewards * PRECISION ) / totalShares;
        }
    }
    
    ///////////////////////////////////////////////
    //////////      Read Functions      ///////////
    ///////////////////////////////////////////////
    
    function shouldDistribute(address shareholder) internal view returns (bool) {
        if (userInfo[shareholder].isRewardExempt || userInfo[shareholder].balance == 0) {
            return false;
        }
        uint256 pending = pendingRewards(shareholder);
        return pending >= minDistribution;
    }

    function getShareForHolder(address holder) external view returns(uint256) {
        return userInfo[holder].balance;
    }

    function pendingRewards(address shareholder) public view returns (uint256 pending) {
        if(userInfo[shareholder].balance == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(userInfo[shareholder].balance);
        uint256 shareholderTotalExcluded = userInfo[shareholder].totalExcluded;

        if ( shareholderTotalDividends > shareholderTotalExcluded ) {
            unchecked {
                pending = shareholderTotalDividends - shareholderTotalExcluded;
            }
        }
    }
    
    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return ( share * dividendsPerShare ) / PRECISION;
    }

    function getHolderAt(uint256 index) external view returns (address) {
        return EnumerableSet.at(holders, index);
    }

    function getNumHolders() external view returns (uint256) {
        return EnumerableSet.length(holders);
    }
}