//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC20.sol";

interface IBaseToken is IERC20 {
    function __init__(bytes calldata payload) external;
    function clone() external returns (address);
}