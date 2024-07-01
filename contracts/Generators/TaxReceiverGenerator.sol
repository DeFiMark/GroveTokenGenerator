//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/Ownable.sol";
import "../interfaces/IExternalGenerator.sol";
import "../interfaces/IImplementation.sol";
import "../lib/Cloneable.sol";

contract TaxReceiverGenerator is Ownable, IExternalGenerator {

    address public implementation;
    event CreatedTaxReceiver(address taxReceiver, address indexed token);

    constructor(address _implementation) {
        implementation = _implementation;
    }
    
    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;
    }

    function generate(address token, bytes calldata payload) external override returns (address) {
        
        // clone implementation
        address taxReceiver = Cloneable(implementation).clone();
        
        // decode payload to attach token to it
        (
            address router_,
            address[] memory _recipients,
            uint256[] memory _allocations,
            address[] memory swapPath_
        ) = abi.decode(payload, (address, address[], uint256[], address[]));

        // attach token to swap path
        address[] memory newSwapPath;
        if (router_ != address(0)) {
            newSwapPath = new address[](swapPath_.length + 1);

            newSwapPath[0] = token;
            for (uint i = 0; i < swapPath_.length; i++) {
                newSwapPath[i + 1] = swapPath_[i];
            }

        } else {
            newSwapPath = swapPath_;
        }

        // encode new payload to include token
        bytes memory newPayload = abi.encode(token, router_, _recipients, _allocations, newSwapPath);

        // initialize taxReceiver
        IImplementation(taxReceiver).__init__(newPayload);
        emit CreatedTaxReceiver(taxReceiver, token);

        // return new address
        return taxReceiver;
    }
}