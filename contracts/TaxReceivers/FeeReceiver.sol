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
    struct TransferType {
        address[] recipients;
        mapping ( address => uint256 ) allocation;
        uint256 totalAllocation;
    }

    // Token to destinations
    mapping ( uint8 => TransferType ) internal tokenTransferTypes;

    // ETH to destinations
    mapping ( uint8 => TransferType ) internal ethTransferTypes;

    // Percentage Of Tokens Sold For ETH
    uint256 public percentToSell;

    // Token Utilized In This Receiver
    address public token;

    // Uniswap Router
    IUniswapV2Router02 public uniswapRouter;

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
            uint256 percentToSell_
        ) = abi.decode(initPayload, (address, address, uint256));
        require(token_ != address(0), 'Invalid Token');
        token = token_;
        if (router_ != address(0)) {
            uniswapRouter = IUniswapV2Router02(router_);
            percentToSell = percentToSell_;
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

    function setPercentToSell(uint256 percentToSell_) external onlyOwner {
        percentToSell = percentToSell_;
    }

    function addRecipient(bool ethType, uint8 transferType, address newRecipient, uint256 newAllocation) external onlyOwner {
        require(
            transferType < 3,
            'Invalid Type'
        );

        // get type from storage
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];

        require(
            tType.allocation[newRecipient] == 0,
            'Already Added'
        );

        // add to list
        tType.recipients.push(newRecipient);

        // set allocation and increase total allocation
        tType.allocation[newRecipient] = newAllocation;
        unchecked {
            tType.totalAllocation += newAllocation;
        }
    }

    function removeRecipient(bool ethType, uint8 transferType, address recipient) external onlyOwner {
        require(
            transferType < 3,
            'Invalid Type'
        );
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];

        // ensure recipient is in the system
        uint256 allocation_ = tType.allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // delete allocation, subtract from total allocation
        delete tType.allocation[recipient];
        unchecked {
            tType.totalAllocation -= allocation_;
        }

        // remove address from array
        uint len = tType.recipients.length;
        uint index = len;
        for (uint i = 0; i < len;) {
            if (tType.recipients[i] == recipient) {
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
        tType.recipients[index] = tType.recipients[len - 1];
        tType.recipients.pop();
    }

    function setAllocation(bool ethType, uint8 transferType, address recipient, uint256 newAllocation) external onlyOwner {
        require(
            transferType < 3,
            'Invalid Type'
        );
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];

        // ensure recipient is in the system
        uint256 allocation_ = tType.allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // adjust their allocation and the total allocation
        tType.allocation[recipient] = ( tType.allocation[recipient] + newAllocation ) - allocation_;
        tType.totalAllocation = ( tType.totalAllocation + newAllocation ) - allocation_;
    }

    /**
        Type: 0 = buy
        Type: 1 = sell
        Type: 2 = transfer
     */
    function trigger(uint8 TRANSFER_TYPE) external {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        // Sell percentage of tokens for ETH
        if (percentToSell > 0) {
            
            // sell tokens for ETH
            uint256 amountToSell = ( tokenBalance * percentToSell ) / 100;
            _sellTokens(amountToSell);

            if (address(this).balance > 0) {

                // distribute ETH to recipients
                uint256[] memory ethDistributions = splitAmount(true, TRANSFER_TYPE, address(this).balance);

                // transfer distributions to each recipient
                uint len = ethDistributions.length;
                for (uint i = 0; i < len;) {
                    _sendETH(ethTransferTypes[TRANSFER_TYPE].recipients[i], ethDistributions[i]);
                    unchecked { ++i; }
                }

            }
        }

        // fetch new balance in case of sell
        tokenBalance = IERC20(token).balanceOf(address(this));

        if (tokenBalance > 0) {
            
            // split balance into distributions
            uint256[] memory distributions = splitAmount(false, TRANSFER_TYPE, IERC20(token).balanceOf(address(this)));

            // transfer distributions to each recipient
            uint len = distributions.length;
            for (uint i = 0; i < len;) {
                _send(token, tokenTransferTypes[TRANSFER_TYPE].recipients[i], distributions[i]);
                unchecked { ++i; }
            }

        }
    }

    function _sellTokens(uint256 amount) internal {
        if (amount == 0 || address(uniswapRouter) == address(0)) {
            return;
        }
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = uniswapRouter.WETH();

        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            1,
            path,
            address(this),
            block.timestamp + 300
        );

        delete path;
    }

    function _sendETH(address to, uint amount) internal {
        TransferHelper.safeTransferETH(to, amount);
    }

    function _send(address token, address to, uint256 amount) internal {
        if (to == address(0) || amount == 0) {
            return;
        }
        if (token == address(0)) {
            _sendETH(to, amount);
        } else {
            TransferHelper.safeTransfer(token, to, amount);
        }
    }

    function getRecipients(bool ethType, uint8 transferType) external view returns (address[] memory) {
        return ethType ? ethTransferTypes[transferType].recipients : tokenTransferTypes[transferType].recipients;
    }

    function splitAmount(bool ethType, uint8 transferType, uint256 amount) public view returns (uint256[] memory distributions) {
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];

        // length of recipient list
        uint256 len = tType.recipients.length;
        distributions = new uint256[](len);

        // loop through recipients, setting their allocations
        for (uint i = 0; i < len;) {
            distributions[i] = ( ( amount * tType.allocation[tType.recipients[i]] ) / tType.totalAllocation );
            unchecked { ++i; }
        }
    }

    function getAllRecipients(bool ethType, uint8 transferType) external view returns (address[] memory) {
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];
        return tType.recipients;
    }

    function getAllocations(bool ethType, uint8 transferType) external view returns (uint256[] memory) {
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];
        uint256 len = tType.recipients.length;
        uint256[] memory allocations = new uint256[](len);
        for (uint i = 0; i < len;) {
            allocations[i] = tType.allocation[tType.recipients[i]];
            unchecked { ++i; }
        }
        return allocations;
    }

    function getTotalAllocation(bool ethType, uint8 transferType) external view returns (uint256) {
        TransferType storage tType = ethType ? ethTransferTypes[transferType] : tokenTransferTypes[transferType];
        return tType.totalAllocation;
    }


    receive() external payable {}
}