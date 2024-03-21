//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IDistributor {
    function setRewardExempt(address wallet, bool rewardless) external;
    function setShare(address shareholder, uint256 amount) external;
    function process() external;
}