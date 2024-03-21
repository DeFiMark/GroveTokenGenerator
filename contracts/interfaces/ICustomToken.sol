//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IBaseToken.sol";

interface ICustomToken is IBaseToken {
    function pairExternalContracts(address[] calldata assets) external;
    function __extra_init__(bytes calldata payload) external;
}


