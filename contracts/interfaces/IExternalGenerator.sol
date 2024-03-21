//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IExternalGenerator {
    function generate(address token, bytes calldata payload) external returns (address);
}