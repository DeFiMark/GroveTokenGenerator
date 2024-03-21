//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/IERC20.sol";
import "./IImplementation.sol";

interface IBaseToken is IERC20, IImplementation {
    function clone() external returns (address);
}