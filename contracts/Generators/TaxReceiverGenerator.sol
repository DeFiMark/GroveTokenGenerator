//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/Ownable.sol";
import "../interfaces/IExternalGenerator.sol";
import "../interfaces/IImplementation.sol";

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
        address taxReceiver = IImplementation(implementation).clone();
        
        // decode payload to attach token to it
        (
            address router,
            uint256 percentToSell
        ) = abi.decode(payload, (address, uint256));

        // encode new payload to include token
        bytes memory newPayload = abi.encode(token, router, percentToSell);

        // initialize taxReceiver
        IImplementation(taxReceiver).__init__(payload);
        emit CreatedTaxReceiver(taxReceiver, token);

        // return new address
        return taxReceiver;
    }
}