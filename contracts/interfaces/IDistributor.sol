//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IImplementation.sol";

interface IDistributor is IImplementation {
    function setRewardExempt(address wallet, bool rewardless) external;
    function setShare(address shareholder, uint256 amount) external;
    function process() external;
}