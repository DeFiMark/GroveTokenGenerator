//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IImplementation {
    function __init__(
        bytes calldata initPayload
    ) external;
}