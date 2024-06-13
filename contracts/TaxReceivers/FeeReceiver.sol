//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/IERC20.sol";
import "../lib/Ownable.sol";
import "../lib/TransferHelper.sol";
import "../lib/IUniswapV2Router02.sol";
import "../lib/Cloneable.sol";
import "../interfaces/IImplementation.sol";

interface IToken {
    function owner() external view returns (address);
}

contract FeeReceiverData {

    // Transfer Types
    address[] public recipients;
    mapping ( address => uint256 ) public allocation;
    uint256 public totalAllocation;

    // Token Utilized In This Receiver
    address public token;

    // Uniswap Router
    IUniswapV2Router02 public uniswapRouter;

    // Swap Path
    address[] public swapPath;

    // only owner
    modifier onlyOwner() {
        require(msg.sender == IToken(token).owner(), 'Not Token Owner');
        _;
    }

}

contract FeeReceiver is FeeReceiverData, Cloneable, IImplementation {

    function __init__(
        bytes calldata initPayload
    ) external override {
        require(token == address(0), 'Already Initialized');
        (
            address token_,
            address router_,
            address[] memory _recipients,
            uint256[] memory _allocations,
            address[] memory swapPath_
        ) = abi.decode(initPayload, (address, address, address[], uint256[], address[]));
        require(token_ != address(0), 'Invalid Token');
        uint len = _recipients.length;
        require(len == _allocations.length, 'Invalid Lengths');
        token = token_;
        if (router_ != address(0)) {
            uniswapRouter = IUniswapV2Router02(router_);
            swapPath = swapPath_;
        }
        for (uint i = 0; i < len;) {
            if (allocation[_recipients[i]] == 0 && _allocations[i] > 0) {
                recipients.push(_recipients[i]);
            }
            unchecked {
                allocation[_recipients[i]] += _allocations[i];
                totalAllocation += _allocations[i];
            }
            unchecked { ++i; }
        }
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        TransferHelper.safeTransfer(token, to, amount);
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        _sendETH(to, amount);
    }

    function setRouter(address router_) external onlyOwner {
        uniswapRouter = IUniswapV2Router02(router_);
    }

    function setSwapPath(address[] calldata swapPath_) external onlyOwner {
        swapPath = swapPath_;
    }

    function addRecipient(address newRecipient, uint256 newAllocation) external onlyOwner {
        require(
            allocation[newRecipient] == 0,
            'Already Added'
        );

        // add to list
        recipients.push(newRecipient);

        // set allocation and increase total allocation
        allocation[newRecipient] = newAllocation;
        unchecked {
            totalAllocation += newAllocation;
        }
    }

    function removeRecipient(address recipient) external onlyOwner {

        // ensure recipient is in the system
        uint256 allocation_ = allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // delete allocation, subtract from total allocation
        delete allocation[recipient];
        unchecked {
            totalAllocation -= allocation_;
        }

        // remove address from array
        uint len = recipients.length;
        uint index = len;
        for (uint i = 0; i < len;) {
            if (recipients[i] == recipient) {
                index = i;
                break;
            }
            unchecked { ++i; }
        }
        require(
            index < len,
            'Recipient Not Found'
        );

        // swap positions with last element then pop last element off
        recipients[index] = recipients[len - 1];
        recipients.pop();
    }

    function setAllocation(address recipient, uint256 newAllocation) external onlyOwner {
       
        // ensure recipient is in the system
        uint256 allocation_ = allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // adjust their allocation and the total allocation
        allocation[recipient] = newAllocation;
        totalAllocation = ( totalAllocation + newAllocation ) - allocation_;
    }

    /**
        Type: 0 = buy
        Type: 1 = sell
        Type: 2 = transfer
     */
    function trigger(uint8) external {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        if (address(uniswapRouter) == address(0)) {

            // distribute tokens to recipients
            uint256[] memory tokenDistributions = splitAmount(tokenBalance);

            // transfer distributions to each recipient
            uint len = tokenDistributions.length;
            for (uint i = 0; i < len;) {
                IERC20(token).transfer(recipients[i], tokenDistributions[i]);
                unchecked { ++i; }
            }

        } else {

            // sell tokens for ETH
            _sellTokens(tokenBalance);

            if (address(this).balance > 0) {

                // distribute ETH to recipients
                uint256[] memory ethDistributions = splitAmount(address(this).balance);

                // transfer distributions to each recipient
                uint len = ethDistributions.length;
                for (uint i = 0; i < len;) {
                    _sendETH(recipients[i], ethDistributions[i]);
                    unchecked { ++i; }
                }

            }

        }
    }

    function _sellTokens(uint256 amount) internal {
        if (amount == 0 || address(uniswapRouter) == address(0) || swapPath.length == 0) {
            return;
        }

        // approve token for router
        IERC20(token).approve(address(uniswapRouter), amount);

        // swap tokens for ETH
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            1,
            swapPath,
            address(this),
            block.timestamp + 300
        );
    }

    function _sendETH(address to, uint amount) internal {
        TransferHelper.safeTransferETH(to, amount);
    }

    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    function splitAmount(uint256 amount) public view returns (uint256[] memory distributions) {

        // length of recipient list
        uint256 len = recipients.length;
        distributions = new uint256[](len);

        // loop through recipients, setting their allocations
        for (uint i = 0; i < len;) {
            distributions[i] = ( ( amount * allocation[recipients[i]] ) / totalAllocation );
            unchecked { ++i; }
        }
    }

    function getAllocations() external view returns (uint256[] memory) {
        uint256 len = recipients.length;
        uint256[] memory allocations = new uint256[](len);
        for (uint i = 0; i < len;) {
            allocations[i] = allocation[recipients[i]];
            unchecked { ++i; }
        }
        return allocations;
    }

    function getTotalAllocation() external view returns (uint256) {
        return totalAllocation;
    }


    receive() external payable {}
}